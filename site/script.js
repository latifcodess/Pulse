// La dernière version de Pulse (releases GitHub) : numéro, lien direct vers le
// DMG et notes de version. Sans réseau, les liens mènent à la page des releases.
(async () => {
  try {
    const response = await fetch("https://api.github.com/repos/latifcodess/Pulse/releases/latest", {
      headers: { Accept: "application/vnd.github+json" },
    });
    if (!response.ok) return;
    const release = await response.json();
    const version = (release.tag_name || "").replace(/^v/, "");
    const dmg = (release.assets || []).find((asset) => asset.name.endsWith(".dmg"));

    if (version) {
      document.querySelectorAll("[data-version]").forEach((element) => { element.textContent = version; });
    }
    if (dmg) {
      document.querySelectorAll("[data-download]").forEach((link) => { link.href = dmg.browser_download_url; });
    }
    if (release.html_url) {
      document.querySelectorAll("[data-notes]").forEach((link) => { link.href = release.html_url; });
    }
  } catch {
    // Pas de réseau ou limite de l'API : on garde les liens par défaut.
  }
})();

// L'heure de la fausse barre des menus : « mer. 18 nov. 19:20 ».
const clock = document.querySelector("[data-clock]");
if (clock) {
  const update = () => {
    const now = new Date();
    const day = now.toLocaleDateString("fr-FR", { weekday: "short", day: "numeric", month: "short" });
    const time = now.toLocaleTimeString("fr-FR", { hour: "2-digit", minute: "2-digit" });
    clock.textContent = `${day} ${time}`;
  };
  update();
  setInterval(update, 30_000);
}
