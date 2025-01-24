import { auth, firestore } from '../../../assets/js/firebaseConfig.js';
import { onAuthStateChanged } from "https://www.gstatic.com/firebasejs/10.8.0/firebase-auth.js";
import { doc, getDoc, setDoc } from "https://www.gstatic.com/firebasejs/10.8.0/firebase-firestore.js";

class ThemeManager {
    constructor() {
        // Sayfa yüklendiğinde hemen varsayılan temayı uygula
        this.applyDefaultTheme();
        this.init();
    }

    applyDefaultTheme() {
        const savedTheme = localStorage.getItem('theme') || 'light';
        document.documentElement.setAttribute('data-theme', savedTheme);
    }

    async init() {
        await this.loadSettings();
        this.setupEventListeners();
    }

    setupEventListeners() {
        this.themeSelect = document.getElementById('themeSelect');
        this.fontSizeSelect = document.getElementById('fontSizeSelect');

        if (this.themeSelect) {
            this.themeSelect.addEventListener('change', () => this.updateTheme());
            const currentTheme = localStorage.getItem('theme') || 'light';
            this.themeSelect.value = currentTheme;
        }

        if (this.fontSizeSelect) {
            this.fontSizeSelect.addEventListener('change', () => this.updateFontSize());
            const currentFontSize = localStorage.getItem('fontSize') || 'medium';
            this.fontSizeSelect.value = currentFontSize;
        }
    }

    async loadSettings() {
        try {
            const user = auth.currentUser;
            if (user) {
                const settingsDoc = await getDoc(doc(firestore, 'userSettings', user.uid));
                if (settingsDoc.exists()) {
                    const settings = settingsDoc.data();
                    this.applyTheme(settings.theme || 'light');
                    this.applyFontSize(settings.fontSize || 'medium');
                }
            }
        } catch (error) {
            console.error('Ayarlar yüklenirken hata:', error);
        }
    }

    applyTheme(theme) {
        document.documentElement.setAttribute('data-theme', theme);
        localStorage.setItem('theme', theme);
    }

    applyFontSize(size) {
        document.documentElement.setAttribute('data-font-size', size);
        localStorage.setItem('fontSize', size);
    }

    updateTheme() {
        const theme = this.themeSelect?.value || 'light';
        this.applyTheme(theme);
        this.saveSettingsToFirestore();
    }

    updateFontSize() {
        const fontSize = this.fontSizeSelect?.value || 'medium';
        this.applyFontSize(fontSize);
        this.saveSettingsToFirestore();
    }

    async saveSettingsToFirestore() {
        try {
            const user = auth.currentUser;
            if (user) {
                const settings = {
                    theme: localStorage.getItem('theme'),
                    fontSize: localStorage.getItem('fontSize')
                };
                await setDoc(doc(firestore, 'userSettings', user.uid), settings, { merge: true });
            }
        } catch (error) {
            console.error('Ayarlar kaydedilirken hata:', error);
        }
    }
}

// Auth state değişikliğini dinle
onAuthStateChanged(auth, async (user) => {
    if (user) {
        const themeManager = new ThemeManager();
    }
});

// Sayfa yüklendiğinde ThemeManager'ı başlat
document.addEventListener('DOMContentLoaded', () => {
    new ThemeManager();
});

// Tema değişikliklerini dinle
window.addEventListener('storage', (event) => {
    if (event.key === 'theme') {
        document.documentElement.setAttribute('data-theme', event.newValue || 'light');
    }
});

export default ThemeManager; 