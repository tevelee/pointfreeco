import Css
import Dependencies
import Either
import Foundation
import Html
import HtmlCssSupport
import HttpPipeline
import HttpPipelineHtmlSupport
import Models
import PointFreePrelude
import PointFreeRouter
import Prelude
import Styleguide
import Tuple

extension Conn where Step == StatusLineOpen, A == Void {
  func showNewBlogPostEmail() -> Conn<ResponseEnded, Data> {
    self.writeStatus(.ok).respond { showNewBlogPostView() }
  }

  func sendNewBlogPostEmail(
    _ id: BlogPost.ID, formData: NewBlogPostFormData?, isTest: Bool?
  ) async -> Conn<ResponseEnded, Data> {
    @Dependency(\.blogPosts) var blogPosts

    do {
      let blogPost = try blogPosts().first(where: { id == $0.id }).unwrap()
      try await sendNewBlogPostEmails(blogPost, formData: formData, isTest: isTest.unwrap())
      return self.redirect(to: .admin())
    } catch {
      return self.redirect(to: .admin(.newBlogPostEmail(.index))) {
        $0.flash(.error, "Could not send new blog post email.")
      }
    }
  }
}

private func showNewBlogPostView() -> Node {
  @Dependency(\.blogPosts) var blogPosts

  return .ul(
    .fragment(
      blogPosts()
        .sorted(by: their(\.id, >))
        .prefix(upTo: 3)
        .map { .li(newBlogPostEmailRowView(post: $0)) }
    )
  )
}

private func newBlogPostEmailRowView(post: BlogPost) -> Node {
  @Dependency(\.siteRouter) var siteRouter

  return .p(
    .text("Blog Post: \(post.title)"),
    .form(
      attributes: [
        .action(siteRouter.path(for: .admin(.newBlogPostEmail(.send(post.id))))),
        .method(.post),
      ],
      .input(
        attributes: [
          .checked(true),
          .name(NewBlogPostFormData.CodingKeys.subscriberDeliver.rawValue),
          .type(.checkbox),
          .value("true"),
        ]
      ),
      .textarea(
        attributes: [
          .name(NewBlogPostFormData.CodingKeys.subscriberAnnouncement.rawValue),
          .placeholder("Subscriber announcement"),
        ]
      ),
      .input(
        attributes: [
          .checked(true),
          .name(NewBlogPostFormData.CodingKeys.nonsubscriberDeliver.rawValue),
          .type(.checkbox),
          .value("true"),
        ]
      ),
      .textarea(
        attributes: [
          .name(NewBlogPostFormData.CodingKeys.nonsubscriberAnnouncement.rawValue),
          .placeholder("Non-subscriber announcement"),
        ]
      ),
      .input(attributes: [.type(.submit), .name("test"), .value("Test email!")]),
      .input(attributes: [.type(.submit), .name("live"), .value("Send email!")])
    )
  )
}

private let fetchBlogPostForId:
  MT<
    Tuple3<BlogPost.ID, NewBlogPostFormData?, Bool?>,
    Tuple3<BlogPost, NewBlogPostFormData?, Bool?>
  > = filterMap(
    over1(fetchBlogPost(forId:) >>> pure) >>> sequence1 >>> map(require1),
    or: redirect(to: .admin(.newBlogPostEmail(.index)))
  )

func fetchBlogPost(forId id: BlogPost.ID) -> BlogPost? {
  @Dependency(\.blogPosts) var blogPosts

  return blogPosts()
    .first(where: { id == $0.id })
}

private func sendNewBlogPostEmails(
  _ post: BlogPost, formData optionalFormData: NewBlogPostFormData?, isTest: Bool
) async {
  @Dependency(\.database) var database

  guard let formData = optionalFormData else {
    return
  }

  let nonsubscriberOrSubscribersOnly: Models.User.SubscriberState?
  switch (formData.nonsubscriberDeliver, formData.subscriberDeliver) {
  case (true, true):
    nonsubscriberOrSubscribersOnly = nil
  case (true, _):
    nonsubscriberOrSubscribersOnly = .nonSubscriber
  case (_, true):
    nonsubscriberOrSubscribersOnly = .subscriber
  case (_, _):
    return
  }

  let users = EitherIO {
    try await isTest
      ? database.fetchAdmins()
      : database
        .fetchUsersSubscribedToNewsletter(.newBlogPost, nonsubscriberOrSubscribersOnly)
  }

  _ = await users
    .mapExcept(bimap(const(unit), id))
    .flatMap { users in
      sendEmail(
        forNewBlogPost: post,
        toUsers: users,
        subscriberAnnouncement: formData.subscriberAnnouncement,
        subscriberDeliver: formData.subscriberDeliver,
        nonsubscriberAnnouncement: formData.nonsubscriberAnnouncement,
        nonsubscriberDeliver: formData.nonsubscriberDeliver,
        isTest: isTest
      )
    }
    .run
    .performAsync()
}

private func sendEmail(
  forNewBlogPost post: BlogPost,
  toUsers users: [User],
  subscriberAnnouncement: String,
  subscriberDeliver: Bool?,
  nonsubscriberAnnouncement: String,
  nonsubscriberDeliver: Bool?,
  isTest: Bool
) -> EitherIO<Prelude.Unit, Prelude.Unit> {

  let subjectPrefix = isTest ? "[TEST] " : ""

  // A personalized email to send to each user.
  let newBlogPostEmails = users.map { user in
    lift(IO { newBlogPostEmail((post, subscriberAnnouncement, nonsubscriberAnnouncement, user)) })
      .flatMap { nodes in
        EitherIO {
          try await sendEmail(
            to: [user.email],
            subject: "\(subjectPrefix)Point-Free Pointer: \(post.title)",
            unsubscribeData: (user.id, .newBlogPost),
            content: inj2(nodes)
          )
        }
        .retry(maxRetries: 3, backoff: { .seconds(10 * $0) })
      }
  }

  // An email to send to admins once all user emails are sent
  let newBlogPostEmailReport = sequence(newBlogPostEmails.map(\.run))
    .flatMap { results in
      EitherIO {
        try await sendEmail(
          to: adminEmails,
          subject: "New blog post email finished sending!",
          content: inj2(
            newBlogPostEmailAdminReportEmail(
              (
                zip(users, results)
                  .filter(second >>> \.isLeft)
                  .map(first),

                results.count
              )
            )
          )
        )
      }
      .run
    }

  let fireAndForget = IO { () -> Prelude.Unit in
    newBlogPostEmailReport
      .map(const(unit))
      .parallel
      .run({ _ in })
    return unit
  }

  return lift(fireAndForget)
}
