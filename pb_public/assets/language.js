// Remember a language only when the visitor explicitly chooses it.
// Direct visits to /de or /en do not need browser storage.
document.querySelectorAll('a[hreflang][lang]').forEach((link) => {
  if (link.lang !== 'de' && link.lang !== 'en') return;
  link.addEventListener('click', () => {
    document.cookie = `hyse_language=${link.lang}; Path=/; Max-Age=15552000; SameSite=Lax; Secure`;
  });
});
