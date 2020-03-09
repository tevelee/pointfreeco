import HttpPipeline
import Models
import PointFreePrelude
import Prelude
import Tuple
import Views

let collectionMiddleware
  : M<Tuple3<User?, SubscriberState, Episode.Collection.Slug>>
  = basicAuth(
    user: Current.envVars.basicAuth.username,
    password: Current.envVars.basicAuth.password
    )
    <<< fetchCollectionMiddleware
    <| map(lower)
    >>> writeStatus(.ok)
    >=> respond(
      view: collectionShow,
      layoutData: { currentUser, currentSubscriberState, collection in
        SimplePageLayoutData(
          currentSubscriberState: currentSubscriberState,
          currentUser: currentUser,
          data: collection,
          extraStyles: collectionsStylesheet,
          style: .base(.some(.minimal(.black))),
          title: collection.title
        )
    }
)

private let fetchCollectionMiddleware
  : MT<
  Tuple3<User?, SubscriberState, Episode.Collection.Slug>,
  Tuple3<User?, SubscriberState, Episode.Collection>
  >
  = filterMap(
    over3(fetchCollection >>> pure) >>> sequence3 >>> map(require3),
    or: routeNotFoundMiddleware
)

private func fetchCollection(_ slug: Episode.Collection.Slug) -> Episode.Collection? {
  Episode.Collection.all.first(where: { $0.slug == slug })
}
