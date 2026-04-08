function formatDate(value) {
  if (!value) return '-';
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return value;
  return date.toLocaleDateString(undefined, {
    year: 'numeric',
    month: 'short',
    day: 'numeric',
  });
}

function formatSize(bytes) {
  if (typeof bytes !== 'number' || Number.isNaN(bytes)) return '-';
  const units = ['B', 'KB', 'MB', 'GB'];
  let value = bytes;
  let unit = units[0];

  for (let i = 0; i < units.length; i += 1) {
    unit = units[i];
    if (value < 1024 || i === units.length - 1) break;
    value /= 1024;
  }

  return `${value.toFixed(unit === 'B' ? 0 : 1)} ${unit}`;
}

async function loadJson(url) {
  const response = await fetch(url, { cache: 'no-store' });
  if (!response.ok) {
    throw new Error(`Failed to load ${url}`);
  }
  return response.json();
}

function renderManifest(manifest) {
  const release = manifest.latest_release;
  const releaseTag = document.getElementById('release-tag');
  const releaseDate = document.getElementById('release-date');
  const releaseLink = document.getElementById('release-link');
  const managerLink = document.getElementById('manager-link');
  const downloadsBody = document.getElementById('downloads-body');

  if (managerLink && manifest.manager_script && manifest.manager_script.raw_url) {
    managerLink.href = manifest.manager_script.raw_url;
  }

  if (!release || !Array.isArray(release.assets) || release.assets.length === 0) {
    if (releaseTag) releaseTag.textContent = 'No release yet';
    if (downloadsBody) {
      downloadsBody.innerHTML = '<tr><td colspan="4" class="muted">No published small binary release found.</td></tr>';
    }
    return;
  }

  if (releaseTag) releaseTag.textContent = release.tag;
  if (releaseDate) releaseDate.textContent = formatDate(release.published_at);
  if (releaseLink) releaseLink.href = release.url;

  downloadsBody.innerHTML = release.assets
    .map((asset) => `
      <tr>
        <td>${asset.arch}</td>
        <td><code>${asset.name}</code></td>
        <td>${formatSize(asset.size)}</td>
        <td><a href="${asset.download_url}">Download</a></td>
      </tr>
    `)
    .join('');
}

function renderUpdates(feed) {
  const managerVersion = document.getElementById('manager-version');
  const updatesList = document.getElementById('updates-list');

  if (managerVersion && feed.manager_version) {
    managerVersion.textContent = `Manager v${feed.manager_version}`;
  }

  if (!updatesList) return;
  if (!Array.isArray(feed.commits) || feed.commits.length === 0) {
    updatesList.innerHTML = '<li class="muted">No script updates found.</li>';
    return;
  }

  updatesList.innerHTML = feed.commits
    .map((commit) => `
      <li class="update-item">
        <h3>${commit.subject}</h3>
        <div class="update-meta">
          <span>${commit.type}</span>
          <span>${formatDate(commit.date)}</span>
          <a href="${commit.url}">${commit.short_sha}</a>
        </div>
      </li>
    `)
    .join('');
}

async function init() {
  const body = document.body;
  const manifestUrl = body.dataset.manifest;
  const updatesUrl = body.dataset.updates;

  try {
    const manifest = await loadJson(manifestUrl);
    renderManifest(manifest);
  } catch (error) {
    const downloadsBody = document.getElementById('downloads-body');
    if (downloadsBody) {
      downloadsBody.innerHTML = '<tr><td colspan="4" class="muted">Failed to load release manifest.</td></tr>';
    }
  }

  try {
    const updates = await loadJson(updatesUrl);
    renderUpdates(updates);
  } catch (error) {
    const updatesList = document.getElementById('updates-list');
    if (updatesList) {
      updatesList.innerHTML = '<li class="muted">Failed to load script updates.</li>';
    }
  }
}

init();
