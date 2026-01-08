window.addEventListener("DOMContentLoaded", () => {
  if (!window.mermaid) return;

  window.mermaid.initialize({
    startOnLoad: true,
    securityLevel: "strict",
  });
});
