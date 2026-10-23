// Run before the stylesheet so a saved choice is present for the first paint.
(() => {
  let theme;
  try {
    theme = localStorage.getItem('version-sentinel-theme');
  } catch {
    // Storage can be blocked; the system preference still works.
  }
  document.documentElement.dataset.theme = theme === 'light' || theme === 'dark'
    ? theme
    : (matchMedia('(prefers-color-scheme: dark)').matches ? 'dark' : 'light');
})();
