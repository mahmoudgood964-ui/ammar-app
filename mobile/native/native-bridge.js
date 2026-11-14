import { App } from '@capacitor/app';
import { Browser } from '@capacitor/browser';
import { Camera, CameraResultType, CameraSource } from '@capacitor/camera';
import { Capacitor } from '@capacitor/core';
import { Haptics, ImpactStyle } from '@capacitor/haptics';
import { Network } from '@capacitor/network';
import { Share } from '@capacitor/share';
import { SplashScreen } from '@capacitor/splash-screen';
import { StatusBar, Style } from '@capacitor/status-bar';

const isNative = Capacitor.isNativePlatform();
if (isNative) {
  document.documentElement.classList.add('ammir-native');

  const safe = (promise) => Promise.resolve(promise).catch((error) => {
    console.debug('[AMMIR native]', error?.message || error);
  });

  async function setupSystemChrome() {
    await safe(StatusBar.setOverlaysWebView({ overlay: false }));
    await safe(StatusBar.setStyle({ style: Style.Dark }));
    await safe(StatusBar.setBackgroundColor({ color: '#f3f5f2' }));
    await safe(SplashScreen.hide({ fadeOutDuration: 250 }));
  }

  function installNetworkStatus() {
    const banner = document.createElement('div');
    banner.id = 'ammirNativeNetworkBanner';
    banner.className = 'ammir-native-network';
    banner.setAttribute('role', 'status');
    banner.setAttribute('aria-live', 'polite');
    banner.textContent = 'لا يوجد اتصال بالإنترنت. ستعود المزامنة عند استعادة الاتصال.';
    document.body.appendChild(banner);

    const update = (connected) => {
      banner.classList.toggle('is-visible', !connected);
      document.documentElement.classList.toggle('ammir-offline', !connected);
    };

    Network.getStatus().then((status) => update(status.connected)).catch(() => update(!navigator.onLine));
    Network.addListener('networkStatusChange', (status) => update(status.connected));
    window.addEventListener('online', () => update(true));
    window.addEventListener('offline', () => update(false));
  }

  async function cameraToInput(input) {
    try {
      const photo = await Camera.getPhoto({
        quality: 86,
        allowEditing: false,
        resultType: CameraResultType.Uri,
        source: CameraSource.Prompt,
        promptLabelHeader: 'إرفاق صورة للمشروع',
        promptLabelPhoto: 'اختيار من الصور',
        promptLabelPicture: 'التقاط صورة'
      });

      if (!photo.webPath) throw new Error('تعذر الوصول إلى الصورة الملتقطة.');
      const response = await fetch(photo.webPath);
      if (!response.ok) throw new Error('تعذر قراءة الصورة من الجهاز.');
      const blob = await response.blob();
      const extension = (blob.type.split('/')[1] || 'jpeg').replace('jpeg', 'jpg');
      const file = new File([blob], 'ammir-site-' + Date.now() + '.' + extension, {
        type: blob.type || 'image/jpeg',
        lastModified: Date.now()
      });
      const transfer = new DataTransfer();
      transfer.items.add(file);
      input.files = transfer.files;
      input.dispatchEvent(new Event('change', { bubbles: true }));
    } catch (error) {
      if (error?.message && !/cancel|cancell?ed/i.test(error.message)) {
        window.alert('تعذر إرفاق الصورة. تحقق من صلاحية الكاميرا أو مكتبة الصور ثم حاول مجدداً.');
        console.warn('[AMMIR camera]', error);
      }
    }
  }

  function addCameraActions(root = document) {
    root.querySelectorAll('input[type="file"][accept]').forEach((input) => {
      if (input.dataset.ammirCameraReady === '1') return;
      if (!input.accept.toLowerCase().includes('image')) return;
      input.dataset.ammirCameraReady = '1';

      const button = document.createElement('button');
      button.type = 'button';
      button.className = 'ammir-native-camera-action';
      button.textContent = 'التقاط صورة بالكاميرا';
      button.addEventListener('click', () => cameraToInput(input));

      const host = input.closest('.field') || input.parentElement;
      if (host) host.appendChild(button);
    });
  }

  function installNativeShare() {
    try {
      Object.defineProperty(navigator, 'share', {
        configurable: true,
        value: async (data = {}) => Share.share({
          title: data.title || 'عَمِّر | AMMIR',
          text: data.text || '',
          url: data.url || window.location.href,
          dialogTitle: 'مشاركة عبر'
        })
      });
    } catch {
      window.AMMIRNativeShare = (data) => Share.share({
        title: data?.title || 'عَمِّر | AMMIR',
        text: data?.text || '',
        url: data?.url || window.location.href,
        dialogTitle: 'مشاركة عبر'
      });
    }
  }

  function installExternalBrowser() {
    document.addEventListener('click', async (event) => {
      const anchor = event.target.closest?.('a[href]');
      if (!anchor || anchor.hasAttribute('download')) return;
      const raw = anchor.getAttribute('href') || '';
      if (!/^https?:\/\//i.test(raw)) return;

      let target;
      try { target = new URL(raw, window.location.href); } catch { return; }
      if (target.origin === window.location.origin) return;
      if (anchor.target === '_self' && target.hostname === 'ammar-app.vercel.app') return;

      event.preventDefault();
      await safe(Browser.open({ url: target.href, presentationStyle: 'popover' }));
    }, true);
  }

  function installHaptics() {
    document.addEventListener('click', (event) => {
      if (event.target.closest?.('button, [role="button"], .btn')) {
        safe(Haptics.impact({ style: ImpactStyle.Light }));
      }
    }, true);
  }

  function installBackButton() {
    App.addListener('backButton', async ({ canGoBack }) => {
      const detail = document.getElementById('detailBackdrop');
      if (detail && getComputedStyle(detail).display !== 'none') {
        const close = detail.querySelector('[data-workspace-close]');
        if (close) { close.click(); return; }
      }

      const modal = [...document.querySelectorAll('.modal-backdrop')].find((node) => getComputedStyle(node).display !== 'none');
      const closeModal = modal?.querySelector('.modal-close, [data-modal-close]');
      if (closeModal) { closeModal.click(); return; }

      if (canGoBack && history.length > 1) {
        history.back();
        return;
      }
      await App.exitApp();
    });
  }

  window.AMMIRNative = Object.freeze({
    isNative: true,
    platform: Capacitor.getPlatform(),
    share: (data) => Share.share({
      title: data?.title || 'عَمِّر | AMMIR',
      text: data?.text || '',
      url: data?.url || window.location.href,
      dialogTitle: 'مشاركة عبر'
    }),
    capturePhoto: cameraToInput
  });

  document.addEventListener('DOMContentLoaded', () => {
    setupSystemChrome();
    installNetworkStatus();
    installNativeShare();
    installExternalBrowser();
    installHaptics();
    installBackButton();
    addCameraActions();
    const observer = new MutationObserver((records) => {
      for (const record of records) {
        record.addedNodes.forEach((node) => {
          if (node.nodeType === Node.ELEMENT_NODE) addCameraActions(node);
        });
      }
    });
    observer.observe(document.body, { childList: true, subtree: true });
  });
}