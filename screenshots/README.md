# Screenshots

**1. GTM tags**

![GTM workspace with two tags](01-gtm-tags-overview.png)

Two tags handle everything: one loads GA4 on every page, and one sends all ten ecommerce events.

---

**2. Ecommerce tag**

![GA4 ecommerce events tag configuration](02-gtm-ga4-ecommerce-tag.png)

`{{Event}}` reuses the dataLayer event name, so one tag covers every event. It adds `shipping_tier` and `payment_type` and passes the ecommerce data.

---

**3. Tag Assistant**

![Tag Assistant summary showing GTM-T6LJLV2J with destination G-M0K4S1JW4C](03-tag-assistant-container-ga4-destination.png)

The container loads on the store and sends to one GA4 property.

---

**4. GA4 custom dimensions**

![GA4 custom definitions with payment_type and shipping_tier](04-ga4-custom-dimensions.png)

Registered before any test orders, so every order can be split by delivery and payment method.

---

**5. On-hold orders**

![WooCommerce orders list with on-hold orders](06-woocommerce-orders-on-hold.png)

Bank-transfer and check orders wait for payment, but GA4 counts them as purchases immediately.

---

**6. Test traffic in attribution**

![WooCommerce orders with origin Referral: tagassistant.google.com](07-woocommerce-orders-referral-origin.png)

Orders placed during GTM Preview show as *Referral: tagassistant.google.com*. The label also stuck to two later orders, so the reconciliation identifies test orders by GA4's debug flag and the publish time instead.
