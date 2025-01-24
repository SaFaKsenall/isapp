// Firebase CDN'lerini ekleyin (bu kısmı HTML'de <script> tag'leri içinde kullanın)
import { initializeApp } from "https://www.gstatic.com/firebasejs/10.8.0/firebase-app.js";
import { getAuth } from "https://www.gstatic.com/firebasejs/10.8.0/firebase-auth.js";
import { getFirestore } from "https://www.gstatic.com/firebasejs/10.8.0/firebase-firestore.js";
import { getDatabase } from "https://www.gstatic.com/firebasejs/10.8.0/firebase-database.js";
import { getStorage } from "https://www.gstatic.com/firebasejs/10.8.0/firebase-storage.js";
import { getAnalytics } from "https://www.gstatic.com/firebasejs/10.8.0/firebase-analytics.js";

// Firebase yapılandırma bilgileri
const firebaseConfig = {
    apiKey: "AIzaSyBL6tHskC6DgfH3D-Vc3CNjBtfSBT6vcYw",
    appId: "1:30004554015:web:f3032a39d6ddf3f5b1e82a",
    messagingSenderId: "30004554015",
    projectId: "jobapp-14c52",
    authDomain: "jobapp-14c52.firebaseapp.com",
    databaseURL: "https://jobapp-14c52-default-rtdb.firebaseio.com",
    storageBucket: "jobapp-14c52.firebasestorage.app",
    measurementId: "G-0MLT93KQHN"
};

// Firebase'i başlat
const app = initializeApp(firebaseConfig);

// Firebase servislerini global olarak tanımla
const auth = getAuth(app);
const firestore = getFirestore(app);
const database = getDatabase(app);
const storage = getStorage(app);
const analytics = getAnalytics(app);

// Servisleri dışa aktar
export {
    auth,
    firestore,
    database,
    storage,
    analytics
};