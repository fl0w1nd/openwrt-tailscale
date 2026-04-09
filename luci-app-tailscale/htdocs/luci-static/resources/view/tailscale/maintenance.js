'use strict';
'require view';
'require rpc';
'require ui';
'require uci';

var _ = function(s) { return s; };

var callGetStatus = rpc.declare({
	object: 'luci-tailscale',
	method: 'get_status',
	expect: { '': {} }
});

var callGetLatestVersions = rpc.declare({
	object: 'luci-tailscale',
	method: 'get_latest_versions',
	expect: { '': {} }
});

var callGetScriptLocalInfo = rpc.declare({
	object: 'luci-tailscale',
	method: 'get_script_local_info',
	expect: { '': {} }
});

var callGetScriptUpdateInfo = rpc.declare({
	object: 'luci-tailscale',
	method: 'get_script_update_info',
	expect: { '': {} }
});

var callListVersions = rpc.declare({
	object: 'luci-tailscale',
	method: 'list_versions',
	params: ['limit'],
	expect: { '': {} }
});

var callListOfficialVersions = rpc.declare({
	object: 'luci-tailscale',
	method: 'list_official_releases',
	params: ['limit'],
	expect: { '': {} }
});

var callDoUpdate = rpc.declare({
	object: 'luci-tailscale',
	method: 'do_update'
});

var callDoInstallVersion = rpc.declare({
	object: 'luci-tailscale',
	method: 'do_install_version',
	params: ['version', 'source']
});

var callUpgradeScripts = rpc.declare({
	object: 'luci-tailscale',
	method: 'upgrade_scripts'
});

var callDoUninstall = rpc.declare({
	object: 'luci-tailscale',
	method: 'do_uninstall'
});

var callGetTaskStatus = rpc.declare({
	object: 'luci-tailscale',
	method: 'get_task_status',
	params: ['task'],
	expect: { '': {} }
});

function makeInfoRow(label, value) {
	return E('div', { 'style': 'display:flex;padding:4px 0' }, [
		E('span', { 'style': 'min-width:180px;font-weight:bold;color:#666' }, label),
		E('span', {}, value || '-')
	]);
}

function pollTaskStatus(task) {
	return callGetTaskStatus(task).then(function(result) {
		if (result && result.done)
			return result;

		return new Promise(function(resolve) {
			window.setTimeout(resolve, 2000);
		}).then(function() {
			return pollTaskStatus(task);
		});
	});
}

function handleAsyncTask(title, message, request, successMessage, errorPrefix, reloadAfterSuccess) {
	ui.showModal(title, [
		E('p', { 'class': 'spinning' }, message)
	]);

	return request.then(function(result) {
		if (result && result.started && result.task) {
			return pollTaskStatus(result.task).then(function(status) {
				ui.hideModal();
				if (status && status.code === 0) {
					ui.addNotification(null, E('p', {}, successMessage), 'info');
					if (reloadAfterSuccess)
						window.setTimeout(function() { window.location.reload(); }, 2000);
				}
				else {
					ui.addNotification(null,
						E('p', {}, errorPrefix + ((status && status.stdout) || 'Unknown error')),
						'danger');
				}
			});
		}

		ui.hideModal();
		if (result && result.code === 0) {
			ui.addNotification(null, E('p', {}, successMessage), 'info');
			if (reloadAfterSuccess)
				window.setTimeout(function() { window.location.reload(); }, 2000);
		}
		else {
			ui.addNotification(null,
				E('p', {}, errorPrefix + ((result && result.stdout) || 'Unknown error')),
				'danger');
		}
	}).catch(function(err) {
		ui.hideModal();
		ui.addNotification(null, E('p', {}, 'RPC error: ' + err.message), 'danger');
	});
}

return view.extend({
	currentStatus: null,
	currentScriptInfo: null,

	load: function() {
		return Promise.all([
			uci.load('tailscale'),
			L.resolveDefault(callGetStatus(), {}),
			L.resolveDefault(callGetScriptLocalInfo(), {})
		]);
	},

	getAutoUpdateEnabled: function() {
		return uci.get('tailscale', 'settings', 'auto_update') === '1';
	},

	renderVersionOverview: function(status) {
		return E('div', { 'class': 'cbi-section' }, [
			E('h3', {}, 'Tailscale Versions'),
			E('div', { 'class': 'cbi-section-descr' },
				'Remote version checks are only performed when you request them.'),
			E('div', { 'style': 'padding:8px 16px' }, [
				makeInfoRow('Installed', status.installed_version || '-'),
				makeInfoRow('Current Source', status.source_type || '-'),
				E('div', { 'style': 'margin-top:12px;display:flex;gap:8px;flex-wrap:wrap' }, [
					E('button', {
						'class': 'cbi-button cbi-button-action',
						'click': ui.createHandlerFn(this, 'handleCheckVersions')
					}, 'Check Remote Versions')
				])
			])
		]);
	},

	renderAutoUpdateSettings: function() {
		var checkbox = E('input', {
			'type': 'checkbox',
			'id': 'ts-maint-auto-update',
			'checked': this.getAutoUpdateEnabled() ? 'checked' : null
		});

		return E('div', { 'class': 'cbi-section' }, [
			E('h3', {}, 'Auto Update'),
			E('div', { 'class': 'cbi-section-descr' },
				'Configure whether Tailscale should automatically check for and install updates.'),
			E('div', { 'style': 'padding:8px 16px' }, [
				E('label', { 'style': 'display:flex;align-items:center;gap:8px' }, [
					checkbox,
					E('span', {}, 'Check for updates daily at 3:30 AM')
				]),
				E('div', { 'style': 'margin-top:12px' }, [
					E('button', {
						'class': 'cbi-button cbi-button-apply',
						'click': ui.createHandlerFn(this, 'handleSaveAutoUpdate')
					}, 'Save Auto Update Setting')
				])
			])
		]);
	},

	renderScriptMaintenance: function(scriptInfo) {
		return E('div', { 'class': 'cbi-section' }, [
			E('h3', {}, 'Manager Scripts'),
			E('div', { 'class': 'cbi-section-descr' },
				'Current script information is local. Remote update checks run only when requested.'),
			E('div', { 'style': 'padding:8px 16px' }, [
				makeInfoRow('Current Version', scriptInfo.current || '-'),
				E('div', { 'style': 'margin-top:12px' }, [
					E('button', {
						'class': 'cbi-button cbi-button-action',
						'click': ui.createHandlerFn(this, 'handleCheckScriptUpdates')
					}, 'Check for Script Updates')
				])
			])
		]);
	},

	renderDangerZone: function() {
		return E('div', { 'class': 'cbi-section' }, [
			E('h3', { 'style': 'color:#d9534f' }, 'Danger Zone'),
			E('div', { 'class': 'cbi-section-descr' },
				'Remove Tailscale binaries, LuCI integration, and related managed files from this router.'),
			E('div', {
				'style': 'padding:12px 16px;border:1px solid #f1b0b7;background:#fff5f5;border-radius:4px'
			}, [
				E('p', { 'style': 'margin:0 0 12px;color:#666' },
					'This action is destructive. Your Tailscale state file will be preserved, but the installed program and management files will be removed.'),
				E('button', {
					'class': 'cbi-button cbi-button-remove',
					'click': ui.createHandlerFn(this, 'handleUninstall')
				}, 'Uninstall Tailscale')
			])
		]);
	},

	renderVersionDialog: function(status, latestVersions, versionList, officialVersionList) {
		var self = this;
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

		return [
			E('p', {}, 'Remote version check completed.'),
			E('div', { 'style': 'padding:4px 0 12px' }, [
				makeInfoRow('Installed', currentVer),
				makeInfoRow('Current Source', sourceType),
				makeInfoRow('Latest Official', latestOfficial || '(check failed)'),
				makeInfoRow('Latest Small', latestSmall || '(check failed)')
			]),
			updateAvailable
				? E('div', { 'style': 'margin:0 0 16px' }, [
					E('button', {
						'class': 'cbi-button cbi-button-apply',
						'click': function() {
							ui.hideModal();
							return self.handleUpdate();
						}
					}, 'Update Current Source to ' + currentLatest)
				])
				: E('p', { 'style': 'color:#666' }, 'Current source is already up to date or could not be checked.'),
			E('div', { 'style': 'margin:16px 0 0;padding-top:12px;border-top:1px solid #eee' }, [
				E('strong', {}, 'Install a specific official version'),
				E('div', { 'style': 'display:flex;gap:8px;align-items:center;margin-top:8px;flex-wrap:wrap' }, [
					officialSelect,
					E('button', {
						'class': 'cbi-button cbi-button-action',
						'click': function() {
							ui.hideModal();
							return self.handleInstallOfficialVersion();
						}
					}, 'Install Official')
				])
			]),
			E('div', { 'style': 'margin:16px 0 0;padding-top:12px;border-top:1px solid #eee' }, [
				E('strong', {}, 'Install a specific small version'),
				E('div', { 'style': 'display:flex;gap:8px;align-items:center;margin-top:8px;flex-wrap:wrap' }, [
					smallSelect,
					E('button', {
						'class': 'cbi-button cbi-button-action',
						'click': function() {
							ui.hideModal();
							return self.handleInstallSmallVersion();
						}
					}, 'Install Small')
				])
			]),
			E('div', { 'class': 'right', 'style': 'margin-top:16px' }, [
				E('button', {
					'class': 'cbi-button',
					'click': ui.hideModal
				}, 'Close')
			])
		];
	},

	renderScriptUpdateDialog: function(scriptInfo) {
		var self = this;
		var statusText = scriptInfo.latest
			? (scriptInfo.update_available ? 'Update available' : 'Up to date')
			: '(check failed)';
		var canUpgrade = !!(scriptInfo && scriptInfo.latest && scriptInfo.update_available);
		var buttonLabel = !scriptInfo.latest
			? 'Check Failed'
			: (scriptInfo.update_available ? 'Upgrade Scripts' : 'Already Up to Date');

		return [
			E('div', { 'style': 'padding:4px 0 12px' }, [
				makeInfoRow('Current Version', scriptInfo.current || '-'),
				makeInfoRow('Latest Version', scriptInfo.latest || '(check failed)'),
				makeInfoRow('Status', statusText)
			]),
			E('div', { 'class': 'right' }, [
				E('button', {
					'class': 'cbi-button',
					'click': ui.hideModal
				}, 'Close'),
				' ',
				E('button', {
					'class': 'cbi-button cbi-button-action',
					'disabled': canUpgrade ? null : 'disabled',
					'click': function() {
						ui.hideModal();
						return self.handleUpgradeScripts(scriptInfo);
					}
				}, buttonLabel)
			])
		];
	},

	render: function(data) {
		this.currentStatus = data[1] || {};
		this.currentScriptInfo = data[2] || {};

		return E('div', { 'class': 'cbi-map' }, [
			E('h2', {}, 'Tailscale Maintenance'),
			E('div', { 'class': 'cbi-map-descr' }, 'Manage versions, updates, scripts, and uninstall.'),
			this.renderVersionOverview(this.currentStatus),
			this.renderAutoUpdateSettings(),
			this.renderScriptMaintenance(this.currentScriptInfo),
			this.renderDangerZone()
		]);
	},

	handleCheckVersions: function() {
		ui.showModal('Checking Remote Versions', [
			E('p', { 'class': 'spinning' }, 'Fetching remote version information...')
		]);

		return Promise.all([
			L.resolveDefault(callGetLatestVersions(), {}),
			L.resolveDefault(callListVersions(20), {}),
			L.resolveDefault(callListOfficialVersions(20), {})
		]).then(L.bind(function(data) {
			ui.showModal('Tailscale Versions',
				this.renderVersionDialog(this.currentStatus || {}, data[0] || {}, data[1] || {}, data[2] || {}));
		}, this)).catch(function(err) {
			ui.hideModal();
			ui.addNotification(null, E('p', {}, 'Failed to load remote versions: ' + err.message), 'danger');
		});
	},

	handleSaveAutoUpdate: function() {
		var checkbox = document.getElementById('ts-maint-auto-update');
		var enabled = checkbox && checkbox.checked ? '1' : '0';

		uci.set('tailscale', 'settings', 'auto_update', enabled);

		ui.showModal('Saving Auto Update Setting', [
			E('p', { 'class': 'spinning' }, 'Saving update policy...')
		]);

		return uci.save().then(function() {
			return uci.apply();
		}).then(function() {
			ui.hideModal();
			ui.addNotification(null,
				E('p', {}, enabled === '1' ? 'Auto Update enabled.' : 'Auto Update disabled.'),
				'info');
		}).catch(function(err) {
			ui.hideModal();
			ui.addNotification(null, E('p', {}, 'Failed to save Auto Update setting: ' + err.message), 'danger');
		});
	},

	handleUpdate: function() {
		return handleAsyncTask(
			'Updating Tailscale',
			'Downloading and installing the latest version...',
			callDoUpdate(),
			'Update successful. Reloading page...',
			'Update failed: ',
			true
		);
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

		return handleAsyncTask(
			'Installing Tailscale v' + version,
			'Downloading and installing version ' + version + ' (' + source + ')...',
			callDoInstallVersion(version, source),
			'Successfully installed version ' + version + '. Reloading page...',
			'Installation failed: ',
			true
		);
	},

	handleCheckScriptUpdates: function() {
		ui.showModal('Checking Script Updates', [
			E('p', { 'class': 'spinning' }, 'Checking remote script version...')
		]);

		return callGetScriptUpdateInfo().then(L.bind(function(scriptInfo) {
			this.currentScriptInfo = scriptInfo || this.currentScriptInfo || {};
			ui.showModal('Manager Script Updates', this.renderScriptUpdateDialog(this.currentScriptInfo));
		}, this)).catch(function(err) {
			ui.hideModal();
			ui.addNotification(null, E('p', {}, 'Failed to check script updates: ' + err.message), 'danger');
		});
	},

	handleUpgradeScripts: function(scriptInfo) {
		if (!scriptInfo || !scriptInfo.latest) {
			ui.addNotification(null, E('p', {}, 'Unable to determine the latest script version.'), 'warning');
			return Promise.resolve();
		}

		if (!scriptInfo.update_available) {
			ui.addNotification(null, E('p', {}, 'Manager scripts are already up to date.'), 'info');
			return Promise.resolve();
		}

		ui.showModal('Upgrading Scripts', [
			E('p', { 'class': 'spinning' }, 'Checking for manager updates and upgrading managed files...')
		]);

		return callUpgradeScripts().then(L.bind(function(result) {
			if (result && result.started && result.task) {
				return pollTaskStatus(result.task).then(L.bind(function(status) {
					return this.handleUpgradeScriptsResult(status);
				}, this));
			}

			return this.handleUpgradeScriptsResult(result);
		}, this)).catch(function(err) {
			ui.hideModal();
			ui.addNotification(null, E('p', {}, 'RPC error: ' + err.message), 'danger');
		});
	},

	handleUpgradeScriptsResult: function(result) {
		var stdout = (result && result.stdout) || '';
		var alreadyCurrent = /Already up to date/i.test(stdout);

		ui.hideModal();

		if (result && result.code === 0) {
			if (alreadyCurrent) {
				ui.addNotification(null, E('p', {}, 'Manager scripts are already up to date.'), 'info');
				return;
			}

			ui.addNotification(null, E('p', {}, 'Scripts upgraded successfully. Reloading page...'), 'info');
			window.setTimeout(function() { window.location.reload(); }, 2000);
			return;
		}

		ui.addNotification(null,
			E('p', {}, 'Script upgrade failed: ' + (stdout || 'Unknown error')),
			'danger');
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
