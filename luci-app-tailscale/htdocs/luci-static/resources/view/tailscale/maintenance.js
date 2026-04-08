'use strict';
'require view';
'require rpc';
'require ui';

var _ = function(s) { return s; };

var callGetStatus = rpc.declare({
	object: 'luci.tailscale',
	method: 'get_status',
	expect: { '': {} }
});

var callGetLatestVersions = rpc.declare({
	object: 'luci.tailscale',
	method: 'get_latest_versions',
	expect: { '': {} }
});

var callGetScriptUpdateInfo = rpc.declare({
	object: 'luci.tailscale',
	method: 'get_script_update_info',
	expect: { '': {} }
});

var callListVersions = rpc.declare({
	object: 'luci.tailscale',
	method: 'list_versions',
	params: ['limit'],
	expect: { '': {} }
});

var callListOfficialVersions = rpc.declare({
	object: 'luci.tailscale',
	method: 'list_official_releases',
	expect: { '': {} }
});

var callDoUpdate = rpc.declare({
	object: 'luci.tailscale',
	method: 'do_update'
});

var callDoInstallVersion = rpc.declare({
	object: 'luci.tailscale',
	method: 'do_install_version',
	params: ['version', 'source']
});

var callUpgradeScripts = rpc.declare({
	object: 'luci.tailscale',
	method: 'upgrade_scripts'
});

var callDoUninstall = rpc.declare({
	object: 'luci.tailscale',
	method: 'do_uninstall'
});

function makeInfoRow(label, value) {
	return E('div', { 'style': 'display:flex;padding:4px 0' }, [
		E('span', { 'style': 'min-width:180px;font-weight:bold;color:#666' }, label),
		E('span', {}, value || '-')
	]);
}

return view.extend({
	load: function() {
		return Promise.resolve({});
	},

	loadData: function() {
		return Promise.all([
			L.resolveDefault(callGetStatus(), {}),
			L.resolveDefault(callGetLatestVersions(), {}),
			L.resolveDefault(callGetScriptUpdateInfo(), {}),
			L.resolveDefault(callListVersions(20), {}),
			L.resolveDefault(callListOfficialVersions(), {})
		]);
	},

	renderVersionManagement: function(status, latestVersions, versionList, officialVersionList) {
		var currentVer = status.installed_version || '-';
		var sourceType = status.source_type || 'official';
		var latestOfficial = latestVersions.official || null;
		var latestSmall = latestVersions.small || null;
		var currentLatest = sourceType === 'small' ? latestSmall : latestOfficial;
		var updateAvailable = currentLatest && currentVer !== '-' && currentLatest !== currentVer;
		var versions = (versionList && versionList.versions) ? versionList.versions : [];
		var officialVersions = (officialVersionList && officialVersionList.versions) ? officialVersionList.versions : [];

		var smallSelect = E('select', { 'class': 'cbi-input-select', 'id': 'ts-small-version' });
		for (var i = 0; i < versions.length; i++)
			smallSelect.appendChild(E('option', { 'value': versions[i] }, versions[i]));

		if (versions.length === 0)
			smallSelect.appendChild(E('option', { 'value': '' }, '(no small versions available)'));

		var officialSelect = E('select', { 'class': 'cbi-input-select', 'id': 'ts-official-version' });
		for (i = 0; i < officialVersions.length; i++)
			officialSelect.appendChild(E('option', { 'value': officialVersions[i] }, officialVersions[i]));

		if (officialVersions.length === 0)
			officialSelect.appendChild(E('option', { 'value': '' }, '(no official versions available)'));

		return E('div', { 'class': 'cbi-section' }, [
			E('h3', {}, 'Tailscale Versions'),
			E('div', { 'style': 'padding:8px 16px' }, [
				makeInfoRow('Installed', currentVer),
				makeInfoRow('Current Source', sourceType),
				makeInfoRow('Latest Official', latestOfficial || '(check failed)'),
				makeInfoRow('Latest Small', latestSmall || '(check failed)'),
				updateAvailable ? E('div', { 'style': 'margin:12px 0' }, [
					E('button', {
						'class': 'cbi-button cbi-button-apply',
						'click': ui.createHandlerFn(this, 'handleUpdate')
					}, 'Update Current Source to ' + currentLatest)
				]) : E('div'),
				E('div', { 'style': 'margin:16px 0 0;padding-top:12px;border-top:1px solid #eee' }, [
					E('strong', {}, 'Install a specific official version'),
					E('div', { 'style': 'display:flex;gap:8px;align-items:center;margin-top:8px;flex-wrap:wrap' }, [
						officialSelect,
						E('button', {
							'class': 'cbi-button cbi-button-action',
							'click': ui.createHandlerFn(this, 'handleInstallOfficialVersion')
						}, 'Install Official')
					])
				]),
				E('div', { 'style': 'margin:16px 0 0;padding-top:12px;border-top:1px solid #eee' }, [
					E('strong', {}, 'Install a specific small version'),
					E('div', { 'style': 'display:flex;gap:8px;align-items:center;margin-top:8px;flex-wrap:wrap' }, [
						smallSelect,
						E('button', {
							'class': 'cbi-button cbi-button-action',
							'click': ui.createHandlerFn(this, 'handleInstallSmallVersion')
						}, 'Install Small')
					])
				])
			])
		]);
	},

	renderScriptMaintenance: function(scriptInfo) {
		var statusText = scriptInfo.latest
			? (scriptInfo.update_available ? 'Update available' : 'Up to date')
			: '(check failed)';

		return E('div', { 'class': 'cbi-section' }, [
			E('h3', {}, 'Manager Scripts'),
			E('div', { 'class': 'cbi-section-descr' },
				'This page checks for manager script updates whenever it is opened.'),
			E('div', { 'style': 'padding:8px 16px' }, [
				makeInfoRow('Current Version', scriptInfo.current || '-'),
				makeInfoRow('Latest Version', scriptInfo.latest || '(check failed)'),
				makeInfoRow('Status', statusText),
				E('div', { 'style': 'margin-top:12px' }, [
					E('button', {
						'class': 'cbi-button cbi-button-action',
						'click': ui.createHandlerFn(this, 'handleUpgradeScripts')
					}, 'Upgrade Scripts')
				])
			])
		]);
	},

	renderDangerZone: function() {
		return E('div', { 'class': 'cbi-section' }, [
			E('h3', {}, 'Maintenance'),
			E('div', { 'style': 'padding:8px 16px' }, [
				E('button', {
					'class': 'cbi-button cbi-button-remove',
					'click': ui.createHandlerFn(this, 'handleUninstall')
				}, 'Uninstall Tailscale')
			])
		]);
	},

	renderLoaded: function(status, latestVersions, scriptInfo, versionList, officialVersionList) {
		var container = E('div', { 'class': 'cbi-map' }, [
			E('h2', {}, 'Tailscale Maintenance'),
			E('div', { 'class': 'cbi-map-descr' }, 'Version management, manager script updates, and uninstall actions.')
		]);

		container.appendChild(this.renderVersionManagement(status, latestVersions, versionList, officialVersionList));
		container.appendChild(this.renderScriptMaintenance(scriptInfo));
		container.appendChild(this.renderDangerZone());
		return container;
	},

	render: function() {
		var placeholder = E('div', { 'class': 'cbi-map' }, [
			E('h2', {}, 'Tailscale Maintenance'),
			E('div', { 'class': 'cbi-map-descr' }, 'Version management, manager script updates, and uninstall actions.'),
			E('div', { 'class': 'cbi-section' }, [
				E('div', { 'style': 'padding:16px;color:#666' }, 'Loading maintenance data...')
			])
		]);

		this.loadData().then(L.bind(function(data) {
			var node = this.renderLoaded(data[0] || {}, data[1] || {}, data[2] || {}, data[3] || {}, data[4] || {});
			placeholder.parentNode.replaceChild(node, placeholder);
		}, this)).catch(function(err) {
			ui.addNotification(null, E('p', {}, 'Failed to load maintenance data: ' + err.message), 'danger');
		});

		return placeholder;
	},

	handleUpdate: function() {
		ui.showModal('Updating Tailscale', [
			E('p', { 'class': 'spinning' }, 'Downloading and installing the latest version...')
		]);

		return callDoUpdate().then(function(result) {
			ui.hideModal();
			if (result && result.code === 0)
				ui.addNotification(null, E('p', {}, 'Update successful.'), 'info');
			else
				ui.addNotification(null,
					E('p', {}, 'Update failed: ' + ((result && result.stdout) || 'Unknown error')),
					'danger');
		}).catch(function(err) {
			ui.hideModal();
			ui.addNotification(null, E('p', {}, 'RPC error: ' + err.message), 'danger');
		});
	},

	handleInstallOfficialVersion: function() {
		var version = document.getElementById('ts-official-version').value;
		return this.handleInstallVersion(version, 'official');
	},

	handleInstallSmallVersion: function() {
		var version = document.getElementById('ts-small-version').value;
		return this.handleInstallVersion(version, 'small');
	},

	handleInstallVersion: function(version, source) {
		if (!version) {
			ui.addNotification(null, E('p', {}, 'Please provide a version.'), 'warning');
			return;
		}

		ui.showModal('Installing Tailscale v' + version, [
			E('p', { 'class': 'spinning' }, 'Downloading and installing version ' + version + ' (' + source + ')...')
		]);

		return callDoInstallVersion(version, source).then(function(result) {
			ui.hideModal();
			if (result && result.code === 0)
				ui.addNotification(null, E('p', {}, 'Successfully installed version ' + version + '.'), 'info');
			else
				ui.addNotification(null,
					E('p', {}, 'Installation failed: ' + ((result && result.stdout) || 'Unknown error')),
					'danger');
		}).catch(function(err) {
			ui.hideModal();
			ui.addNotification(null, E('p', {}, 'RPC error: ' + err.message), 'danger');
		});
	},

	handleUpgradeScripts: function() {
		ui.showModal('Upgrading Scripts', [
			E('p', { 'class': 'spinning' }, 'Checking for manager updates and upgrading managed files...')
		]);

		return callUpgradeScripts().then(function(result) {
			ui.hideModal();
			if (result && result.code === 0) {
				ui.addNotification(null,
					E('p', {}, (result.stdout && result.stdout.trim()) || 'Scripts upgraded successfully. Reloading page...'),
					'info');
				window.setTimeout(function() { window.location.reload(); }, 2000);
			}
			else {
				ui.addNotification(null,
					E('p', {}, 'Script upgrade failed: ' + ((result && result.stdout) || 'Unknown error')),
					'danger');
			}
		}).catch(function(err) {
			ui.hideModal();
			ui.addNotification(null, E('p', {}, 'RPC error: ' + err.message), 'danger');
		});
	},

	handleUninstall: function() {
		ui.showModal('Confirm Uninstall', [
			E('p', {}, 'This will remove Tailscale binaries, scripts, configuration, and LuCI app files. The state file will be preserved.'),
			E('div', { 'class': 'right' }, [
				E('button', {
					'class': 'cbi-button',
					'click': ui.hideModal
				}, 'Cancel'),
				' ',
				E('button', {
					'class': 'cbi-button cbi-button-remove',
					'click': function() {
						ui.showModal('Uninstalling Tailscale', [
							E('p', { 'class': 'spinning' }, 'Removing Tailscale...')
						]);

						callDoUninstall().then(function(result) {
							ui.hideModal();
							if (result && result.code === 0) {
								ui.addNotification(null, E('p', {}, 'Tailscale uninstalled. Reloading page...'), 'info');
								window.setTimeout(function() { window.location.reload(); }, 2000);
							}
							else {
								ui.addNotification(null,
									E('p', {}, 'Uninstall failed: ' + ((result && result.stdout) || 'Unknown error')),
									'danger');
							}
						}).catch(function(err) {
							ui.hideModal();
							ui.addNotification(null, E('p', {}, 'RPC error: ' + err.message), 'danger');
						});
					}
				}, 'Uninstall')
			])
		]);
	},

	handleSaveApply: null,
	handleSave: null,
	handleReset: null
});
