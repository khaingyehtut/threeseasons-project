importScripts('https://www.gstatic.com/firebasejs/10.7.1/firebase-app-compat.js');
importScripts('https://www.gstatic.com/firebasejs/10.7.1/firebase-messaging-compat.js');

firebase.initializeApp({
  apiKey: 'AIzaSyB6W5xNuHSqRpC6JMYS2hhvk6Qt28tAF5E',
  authDomain: 'ecommerce-project-32c41.firebaseapp.com',
  projectId: 'ecommerce-project-32c41',
  storageBucket: 'ecommerce-project-32c41.firebasestorage.app',
  messagingSenderId: '751030563947',
  appId: '1:751030563947:web:2f26b05ce47aab6f9aed2e',
});

const messaging = firebase.messaging();

// Handle background FCM messages (app tab not active or browser minimised)
messaging.onBackgroundMessage(function (payload) {
  const title = payload.notification?.title || payload.data?.title || 'Three Seasons';
  const body  = payload.notification?.body  || payload.data?.body  || '';
  return self.registration.showNotification(title, {
    body,
    icon: '/icons/Icon-192.png',
    badge: '/icons/Icon-192.png',
  });
});
