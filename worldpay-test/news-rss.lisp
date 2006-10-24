(in-package :bos.m2)

(defmethod rss-item-channel ((item news-item))
  "news")

(defmethod rss-item-published ((item news-item))
  (news-item-published item (worldpay-test::current-website-language)))

(defmethod rss-item-title ((item news-item))
  (news-item-title item (worldpay-test::current-website-language)))

(defmethod rss-item-description ((item news-item))
  (news-item-text item (worldpay-test::current-website-language)))

(defmethod rss-item-link ((item news-item))
  (format nil "http://createrainforest.org/~A/news-extern/~A" (worldpay-test::current-website-language) (store-object-id item)))

(defmethod rss-item-guid ((item news-item))
  (format nil "http://createrainforest.org/~A/news-extern/~A" (worldpay-test::current-website-language) (store-object-id item)))

(defmethod rss-item-pub-date ((item news-item))
  (news-item-time item))
