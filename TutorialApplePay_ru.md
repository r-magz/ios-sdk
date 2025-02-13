# Настройка Apple Pay

В начале необходимо пройти пункт 1, 2 из [инструкции интеграции SDK](Tutorial_ru.md)

## 1. Использование SDK

1.1 Реализовать функцию cardKitViewController

```swift
//SampleCardKPaymentView.swift
extension SampleCardKPaymentView: CardKDelegate {
  func cardKitViewController(_ controller: CardKViewController, didCreateSeToken seToken: String, allowSaveBinding: Bool, isNewCard: Bool) {
    debugPrint(seToken)

    let alert = UIAlertController(title: "SeToken", message: seToken, preferredStyle: UIAlertController.Style.alert)
    alert.addAction(UIAlertAction(title: "OK", style: UIAlertAction.Style.default, handler: nil))

    controller.present(alert, animated: true)

  }
  ...
}
```

1.2 Реализовать функцию `didLoad(\_ controller: CardKViewController)`

В функции `didLoad(\_ controller: CardKViewController)` присваиваются атрибуты контроллера `CardKViewController`

```swift
//ViewController.swift
extension ViewController: CardKDelegate {
  ...
  func didLoad(_ controller: CardKViewController) {
    controller.allowedCardScaner = CardIOUtilities.canReadCardWithCamera();
    controller.purchaseButtonTitle = "Custom purchase button";
    controller.allowSaveBinding = true;
    controller.isSaveBinding = true;
    controller.displayCardHolderField = true;
  }
  ...
}
```

1.3 Реализовать функцию `willShow(_ paymentView: CardKPaymentView)`

```swift
//
extension ViewController: CardKDelegate {
  ...
  func willShow(_ paymentView: CardKPaymentView) {
    let paymentNetworks = [PKPaymentNetwork.amex, .discover, .masterCard, .visa]
    let paymentItem = PKPaymentSummaryItem.init(label: "Test", amount: NSDecimalNumber(value: 10))
    let merchandId = "t";
    paymentView.merchantId = merchandId
    paymentView.paymentRequest.currencyCode = "USD"
    paymentView.paymentRequest.countryCode = "US"
    paymentView.paymentRequest.merchantIdentifier = merchandId
    paymentView.paymentRequest.merchantCapabilities = PKMerchantCapability.capability3DS
    paymentView.paymentRequest.supportedNetworks = paymentNetworks
    paymentView.paymentRequest.paymentSummaryItems = [paymentItem]
    paymentView.paymentButtonStyle = .black;
    paymentView.paymentButtonType = .buy;

    paymentView.cardPaybutton.backgroundColor = .white;
    paymentView.cardPaybutton.setTitleColor(.black, for: .normal);
    paymentView.cardPaybutton.setTitle("Custom title", for: .normal);
  }
  ...
}
```

1.4 Отобразить CardKPaymentView

```swift
//ViewController.swift
...
@objc func _openController() {
  CardKConfig.shared.theme = CardKTheme.light();
  CardKConfig.shared.language = "";
  CardKConfig.shared.bindingCVCRequired = true;
  CardKConfig.shared.bindings = [];
  CardKConfig.shared.isTestMod = true;
  CardKConfig.shared.mdOrder = "mdOrder";

  let cardKPaymentView = CardKPaymentView.init(delegate: self);
  cardKPaymentView.controller = self;
  cardKPaymentView.frame = CGRect(x: width * 0.5 - 50, y: height * 0.5 - 300, width: 100, height: 100);
  self.view.addSubview(cardKPaymentView);
}
...
```

**Результат:**

<div align="center">
  <div align="inline">
  <img src="./images/apple_pay_buttons.png" width="300"/>
  <div align="center"> Рисунок 1.1. Пример контроллера с apple pay кнопками </div>
  </div>
</div>
