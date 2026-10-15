(() => {
  'use strict';
  let promptEvent;
  const ua = navigator.userAgent;
  const platform = /iPad|iPhone|iPod/.test(ua) || (navigator.platform === 'MacIntel' && navigator.maxTouchPoints > 1) ? 'ios' : /Android/.test(ua) ? 'android' : /Mac/.test(ua) ? 'mac' : /Windows/.test(ua) ? 'windows' : 'other';
  const installed = () => window.matchMedia('(display-mode: standalone)').matches || navigator.standalone === true;
  window.addEventListener('beforeinstallprompt', e => { e.preventDefault(); promptEvent = e; });
  window.addEventListener('appinstalled', () => { promptEvent = null; });
  const help = {
    windows: 'On Windows, open this website in Chrome or Edge. Use the install icon in the address bar, or the browser menu → Apps / Install. If it is already installed, open YKonnect from the Start menu.',
    android: 'On Android, open this website in Chrome. Open the browser menu → Add to Home screen / Install app. Confirm the installation.',
    ios: 'On your iPhone or iPad, open this website in Safari. Tap Share → Add to Home Screen → Add. If shown, leave Open as Web App enabled.',
    mac: 'On a Mac, open this website in Safari and choose File → Add to Dock where available. In Chrome, use the install icon in the address bar or its install menu.'
  };
  document.querySelectorAll('[data-platform]').forEach(button => button.addEventListener('click', async () => {
    const target = button.dataset.platform;
    if (target === platform && promptEvent && !installed()) {
      const event = promptEvent; promptEvent = null;
      try { await event.prompt(); await event.userChoice; } catch (_) { showHelp(target); }
    } else showHelp(target);
  }));
  function showHelp(target) {
    document.getElementById('help-text').textContent = help[target];
    document.getElementById('install-help').showModal();
  }
  if ('serviceWorker' in navigator && window.isSecureContext) {
    navigator.serviceWorker.register('./sw.js', {updateViaCache: 'none'}).then(reg => {
      const showUpdate = () => {
        if (reg.waiting) document.getElementById('update').textContent = 'An update is ready. Save your work, then close all YKonnect windows and tabs and reopen the app. No reinstall needed.';
      };
      showUpdate();
      reg.addEventListener('updatefound', () => {
        const worker = reg.installing;
        if (worker) worker.addEventListener('statechange', showUpdate);
      });
      document.addEventListener('visibilitychange', () => {
        if (document.visibilityState === 'visible' && navigator.onLine) reg.update().catch(() => {});
      });
    }).catch(() => { document.getElementById('update').textContent = 'Offline startup is not ready. Reopen this page online to try again.'; });
  }
})();
