import Css
import Either
import Foundation
import Html
import HtmlCssSupport
import HttpPipeline
import HttpPipelineHtmlSupport
import Models
import Optics
import Prelude
import Stripe
import Styleguide
import Tuple
import View

let paymentInfoResponse =
  filterMap(require1 >>> pure, or: loginAndRedirect)
    <<< requireStripeSubscription
    <| writeStatus(.ok)
    >=> map(lower)
    >>> respond(
      view: paymentInfoView,
      layoutData: { subscription, currentUser, formFields, subscriberState in
        SimplePageLayoutData(
          currentSubscriberState: subscriberState,
          currentUser: currentUser,
          data: (subscription, formFields),
          title: "Update Payment Info"
        )
    }
)

private let genericPaymentInfoError = """
We couldn’t update your payment info at this time. Please try again later or contact
<support@pointfree.co>.
"""

let updatePaymentInfoMiddleware:
  Middleware<StatusLineOpen, ResponseEnded, Tuple2<User?, Stripe.Token.Id?>, Data> =
  filterMap(require1 >>> pure, or: loginAndRedirect)
    <<< filterMap(
      require2 >>> pure,
      or: redirect(
        to: .account(.paymentInfo(.show(expand: nil))),
        headersMiddleware: flash(.error, genericPaymentInfoError)
      )
    )
    <<< requireStripeSubscription
    <| { conn in
      let (subscription, _, token) = lower(conn.data)

      return Current.stripe.updateCustomer(subscription.customer.either(id, ^\.id), token)
        .run
        .flatMap {
          conn |> redirect(
            to: .account(.paymentInfo(.show(expand: nil))),
            headersMiddleware: $0.isLeft
              ? flash(.error, genericPaymentInfoError)
              : flash(.notice, "Your payment information has been updated.")
          )
      }
}

let paymentInfoView = View<(Stripe.Subscription, PricingFormStyle)> { subscription, formFields in

  gridRow([
    gridColumn(sizes: [.mobile: 12, .desktop: 8], [style(margin(leftRight: .auto))], [
      div([`class`([Class.padding([.mobile: [.all: 3], .desktop: [.all: 4]])])],
          titleRowView.view(unit)
            <> (subscription.customer.right?.sources.data.first.map(currentPaymentInfoRowView.view) ?? [])
            <> updatePaymentInfoRowView.view(formFields)
      )
      ])
    ])
}

private let titleRowView = View<Prelude.Unit> { _ in
  gridRow([`class`([Class.padding([.mobile: [.bottom: 2]])])], [
    gridColumn(sizes: [.mobile: 12], [
      div([
        h1([`class`([Class.pf.type.responsiveTitle3])], ["Payment Info"])
        ])
      ])
    ])
}

private let currentPaymentInfoRowView = View<Stripe.Card> { card in
  gridRow([`class`([Class.padding([.mobile: [.bottom: 2]])])], [
    gridColumn(sizes: [.mobile: 12], [
      div([
        h2([`class`([Class.pf.type.responsiveTitle4])], ["Current Payment Info"]),
        p([.text(card.brand.rawValue + " ending in " + String(card.last4))]),
        p([.text("Expires " + String(card.expMonth) + "/" + String(card.expYear))]),
        ])
      ])
    ])
}

private let updatePaymentInfoRowView = View<PricingFormStyle> { formStyle in
  return gridRow([`class`([Class.padding([.mobile: [.bottom: 4]])])], [
    gridColumn(sizes: [.mobile: 12], [
      div([
        h2([`class`([Class.pf.type.responsiveTitle4])], ["Update"]),
        form(
          [action(path(to: .account(.paymentInfo(.update(nil))))), id(StripeHtml.formId), method(.post)],
          StripeHtml.cardInput(couponId: nil, formStyle: formStyle)
            <> StripeHtml.errors
            <> StripeHtml.scripts
            <> [
              button(
                [`class`([Class.pf.components.button(color: .purple), Class.margin([.mobile: [.top: 3]])])],
                ["Update payment info"]
              ),
              a(
                [
                  href(path(to: .account(.index))),
                  `class`([Class.pf.components.button(color: .black, style: .underline)])
                ],
                ["Cancel"]
              )
          ]
        )
      ])
    ])
  ])
}
