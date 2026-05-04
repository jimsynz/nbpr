# Catalogue

The list below is fetched live from the Hex API on page load —
whatever's in the `nbpr` organisation right now. No rebuild required
when a new package lands.

Retired packages are filtered out automatically. The `:nbpr` library
itself isn't shown because it lives on public hex.pm rather than the
`nbpr` organisation; install it directly from
[hex.pm/packages/nbpr](https://hex.pm/packages/nbpr).

<style>
  #nbpr-catalogue table { width: 100%; border-collapse: collapse; }
  #nbpr-catalogue th, #nbpr-catalogue td { padding: 0.5rem 0.75rem; text-align: left; vertical-align: top; border-bottom: 1px solid #e0e0e0; }
  #nbpr-catalogue th { font-weight: 600; }
  #nbpr-catalogue td code { white-space: nowrap; }
  #nbpr-catalogue .empty, #nbpr-catalogue .error { padding: 1rem 0; color: #555; }
</style>

<div id="nbpr-catalogue">
  <p class="empty">Loading from hex.pm…</p>
</div>

<script>
(function () {
  var TARGET = document.getElementById("nbpr-catalogue");
  var KEY = "15da04a2330d881e1301a73c5d39f591";
  var API = "https://hex.pm/api/repos/nbpr/packages";

  function escapeHtml(s) {
    return String(s).replace(/[&<>"']/g, function (c) {
      return { "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c];
    });
  }

  function isRetired(pkg) {
    var latest = pkg.latest_stable_version || pkg.latest_version;
    return latest && pkg.retirements && pkg.retirements[latest];
  }

  function shouldShow(pkg) {
    if (!pkg.name) return false;
    if (pkg.name.indexOf("nbpr_") !== 0) return false; // only :nbpr_* binaries
    if (isRetired(pkg)) return false;
    return true;
  }

  function render(pkgs) {
    var visible = pkgs.filter(shouldShow).sort(function (a, b) {
      return a.name.localeCompare(b.name);
    });

    if (visible.length === 0) {
      TARGET.innerHTML = '<p class="empty">No packages published yet.</p>';
      return;
    }

    var rows = visible.map(function (p) {
      var v = p.latest_stable_version || p.latest_version || "";
      var desc = (p.meta && p.meta.description) || "";
      return (
        "<tr>" +
        '<td><a href="' + escapeHtml(p.html_url) + '">' + escapeHtml(p.name) + "</a></td>" +
        "<td><code>" + escapeHtml(v) + "</code></td>" +
        "<td>" + escapeHtml(desc) + "</td>" +
        "</tr>"
      );
    }).join("");

    TARGET.innerHTML =
      "<table><thead><tr>" +
      "<th>Package</th><th>Version</th><th>Description</th>" +
      "</tr></thead><tbody>" +
      rows +
      "</tbody></table>";
  }

  function showError(msg) {
    TARGET.innerHTML =
      '<p class="error">Couldn\'t load the catalogue from the Hex API: ' +
      escapeHtml(msg) +
      '</p>' +
      '<p class="error">The current list is also visible at ' +
      '<a href="https://hex.pm/orgs/nbpr/packages">hex.pm/orgs/nbpr</a>.</p>';
  }

  if (location.protocol === "file:") {
    TARGET.innerHTML =
      '<p class="error">Local preview note: browsers block <code>fetch()</code> ' +
      "from <code>file://</code> origins, so the live list won't load when you " +
      "open the generated HTML directly.</p>" +
      '<p class="error">Serve the docs over HTTP to test:</p>' +
      "<pre><code>mix docs &amp;&amp; cd doc &amp;&amp; python3 -m http.server</code></pre>" +
      '<p class="error">Or browse the deployed copy on ' +
      '<a href="https://hexdocs.pm/nbpr">hexdocs.pm/nbpr</a>.</p>';
    return;
  }

  fetch(API, { headers: { Authorization: KEY, Accept: "application/json" } })
    .then(function (r) {
      if (!r.ok) throw new Error("HTTP " + r.status);
      return r.json();
    })
    .then(render)
    .catch(function (err) {
      showError(err && err.message ? err.message : String(err));
    });
})();
</script>

## How this list updates

Each binary package's release pipeline tags + publishes to the `nbpr`
Hex organisation independently of the `:nbpr` library itself. A page
generated at library-publish time would only refresh when `:nbpr` is
re-published — out of date the moment a new binary package lands.

Fetching at page load avoids that. Every visit to this page asks the
Hex API for the current state of the organisation. The
[organisation's read key](https://hex.pm/api/repos/nbpr/packages) is
intentionally public, so the call works without anyone authenticating.

If the Hex API is unreachable or returns an error, a fallback link to
[hex.pm/orgs/nbpr](https://hex.pm/orgs/nbpr) is shown.
