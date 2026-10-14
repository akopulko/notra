const root = document.documentElement;
const themeToggle = document.querySelector('.theme-toggle');
const mobileMenu = document.querySelector('.menu-toggle');
const mobileNav = document.querySelector('#mobile-nav');
const githubButtonHost = document.querySelector('.github-button-host');
const screenshots = document.querySelectorAll('img[data-src-dark][data-src-light]');
let githubRenderGeneration = 0;
const loadGithubRenderer = import('https://esm.sh/github-buttons@2.33.1')
  .then(({ render }) => render)
  .catch((error) => {
    console.error('Unable to load the GitHub button renderer.', error);
    return null;
  });

function renderGithubButton(theme) {
  if (!githubButtonHost) return;

  const generation = ++githubRenderGeneration;
  const fallback = document.createElement('a');
  fallback.href = 'https://github.com/akopulko/notra';
  fallback.setAttribute('aria-label', 'GitHub repository stars');
  fallback.innerHTML = '<img class="github-mark github-mark-light" src="assets/icons/github-mark-dark.svg" alt="" aria-hidden="true" width="98" height="96"><img class="github-mark github-mark-dark" src="assets/icons/github-mark-light.svg" alt="" aria-hidden="true" width="98" height="96">';
  githubButtonHost.replaceChildren(fallback);

  loadGithubRenderer.then((render) => {
    if (!render || generation !== githubRenderGeneration) return;

    render({
      href: 'https://github.com/akopulko/notra',
      'aria-label': 'GitHub repository stars',
      'data-icon': 'mark-github',
      'data-show-count': 'true',
      'data-size': 'large',
      'data-color-scheme': theme,
      'data-text': ''
    }, (button) => {
      if (generation === githubRenderGeneration) githubButtonHost.replaceChildren(button);
    });
  });
}

function setTheme(theme, persist = true) {
  root.dataset.theme = theme;
  screenshots.forEach((image) => {
    const source = theme === 'light' ? image.dataset.srcLight : image.dataset.srcDark;
    if (image.getAttribute('src') !== source) image.src = source;
  });
  document.querySelector('meta[name="theme-color"]').content = getComputedStyle(root).getPropertyValue('--bg').trim();
  if (persist) localStorage.setItem('notra-theme', theme);
  const nextTheme = theme === 'dark' ? 'light' : 'dark';
  themeToggle.setAttribute('aria-label', `Switch to ${nextTheme} theme`);
  themeToggle.setAttribute('aria-pressed', String(theme === 'light'));
  renderGithubButton(theme);
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
