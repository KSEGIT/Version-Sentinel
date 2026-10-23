import { initTerminalDemo } from './terminal.js';

/** @param {Document} root */
export function initThemeToggle(root) {
  const button = root.getElementById('theme-toggle');
  if (!button) return;
  const systemTheme = matchMedia('(prefers-color-scheme: dark)');
  const reducedMotion = matchMedia('(prefers-reduced-motion: reduce)');
  let explicit = false;
  try {
    const stored = localStorage.getItem('version-sentinel-theme');
    explicit = stored === 'light' || stored === 'dark';
  } catch {
    // Keep an explicit choice in memory when storage is blocked.
  }
  let theme = root.documentElement.dataset.theme;
  let transition;
  const applyTheme = () => {
    root.documentElement.dataset.theme = theme;
    button.setAttribute('aria-label', `Switch to ${theme === 'dark' ? 'light' : 'dark'} theme`);
  };
  systemTheme.addEventListener('change', event => {
    if (explicit) return;
    theme = event.matches ? 'dark' : 'light';
    applyTheme();
  });
  reducedMotion.addEventListener('change', event => {
    if (event.matches) transition?.skipTransition();
  });
  button.addEventListener('click', () => {
    explicit = true;
    theme = theme === 'dark' ? 'light' : 'dark';
    try {
      localStorage.setItem('version-sentinel-theme', theme);
    } catch {
      // This session's choice remains active even if it cannot be saved.
    }
    transition?.skipTransition();
    if (typeof root.startViewTransition === 'function' && !reducedMotion.matches) {
      transition = root.startViewTransition(applyTheme);
      // A skipped transition rejects ready even though its update still runs.
      transition.ready.catch(error => {
        if (error.name !== 'AbortError' && error.name !== 'InvalidStateError') console.warn('Theme transition unavailable:', error);
      });
    } else {
      applyTheme();
    }
  });
  applyTheme();
  button.hidden = false;
}

/** @param {Document} root */
export function initCopyControls(root) {
  const status = root.getElementById('copy-status');
  if (!status) return;
  for (const button of root.querySelectorAll('[data-copy-target]')) {
    const code = root.getElementById(button.dataset.copyTarget);
    const feedback = root.getElementById(`${button.dataset.copyTarget}-feedback`);
    if (!code || !feedback) continue;
    button.addEventListener('click', async () => {
      // Clear the shared region so a repeated action can be announced again.
      status.textContent = '';
      let message;
      try {
        await navigator.clipboard.writeText(code.textContent);
        message = 'Commands copied to clipboard.';
      } catch {
        message = 'Clipboard unavailable. Select the visible commands and copy them manually.';
      }
      feedback.textContent = message;
      status.textContent = message;
    });
    button.hidden = false;
  }
}

/** @param {Document} root */
export function initInstallTabs(root) {
  const selectors = root.querySelector('.install-selectors');
  if (!selectors) return;
  const tabs = [...selectors.querySelectorAll('a[href^="#"]')];
  const panels = tabs.map(tab => root.getElementById(tab.hash.slice(1)));
  if (!tabs.length || panels.some(panel => !panel)) return;
  const select = index => {
    tabs.forEach((tab, current) => {
      const active = current === index;
      tab.setAttribute('aria-selected', String(active));
      tab.tabIndex = active ? 0 : -1;
      panels[current].hidden = !active;
    });
  };
  const selectFragment = () => {
    const index = tabs.findIndex(tab => tab.hash === location.hash);
    if (index !== -1) select(index);
  };
  tabs.forEach((tab, index) => {
    tab.addEventListener('click', event => {
      if (event.metaKey || event.ctrlKey || event.shiftKey || event.altKey) return;
      event.preventDefault();
      select(index);
      if (location.hash !== tab.hash) history.pushState(null, '', tab.hash);
    });
    tab.addEventListener('keydown', event => {
      let next;
      if (event.key === 'ArrowRight') next = (index + 1) % tabs.length;
      else if (event.key === 'ArrowLeft') next = (index - 1 + tabs.length) % tabs.length;
      else if (event.key === 'Home') next = 0;
      else if (event.key === 'End') next = tabs.length - 1;
      else if (event.key === ' ') next = index;
      else return;
      event.preventDefault();
      select(next);
      tabs[next].focus();
    });
    for (const link of root.querySelectorAll(`a[href="${tab.hash}"]`)) {
      if (link !== tab) link.addEventListener('click', () => select(index));
    }
  });
  window.addEventListener('hashchange', selectFragment);
  // Semantics and hidden panels are applied only after all handlers are ready.
  selectors.setAttribute('role', 'tablist');
  tabs.forEach((tab, index) => {
    tab.id = `${panels[index].id}-tab`;
    tab.setAttribute('role', 'tab');
    tab.setAttribute('aria-controls', panels[index].id);
    panels[index].setAttribute('role', 'tabpanel');
    panels[index].setAttribute('aria-labelledby', tab.id);
    panels[index].tabIndex = 0;
  });
  select(0);
  selectFragment();
}

initThemeToggle(document);
initCopyControls(document);
initInstallTabs(document);

initTerminalDemo(document);
