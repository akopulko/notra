const root = document.documentElement;
const themeToggle = document.querySelector('.theme-toggle');
const mobileMenu = document.querySelector('.menu-toggle');
const mobileNav = document.querySelector('#mobile-nav');

function setTheme(theme, persist = true) {
  root.dataset.theme = theme;
  if (persist) localStorage.setItem('notra-theme', theme);
  const nextTheme = theme === 'dark' ? 'light' : 'dark';
  themeToggle.setAttribute('aria-label', `Switch to ${nextTheme} theme`);
  themeToggle.setAttribute('aria-pressed', String(theme === 'light'));
}

setTheme(root.dataset.theme, false);
themeToggle.addEventListener('click', () => setTheme(root.dataset.theme === 'dark' ? 'light' : 'dark'));

mobileMenu.addEventListener('click', () => {
  const isOpen = mobileMenu.getAttribute('aria-expanded') === 'true';
  mobileMenu.setAttribute('aria-expanded', String(!isOpen));
  mobileMenu.setAttribute('aria-label', isOpen ? 'Open navigation' : 'Close navigation');
  mobileNav.hidden = isOpen;
});

mobileNav.querySelectorAll('a').forEach((link) => {
  link.addEventListener('click', () => {
    mobileMenu.setAttribute('aria-expanded', 'false');
    mobileMenu.setAttribute('aria-label', 'Open navigation');
    mobileNav.hidden = true;
  });
});
