'use strict';
'require view';
'require form';
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

	renderInstalledVersions: function(status, scriptInfo) {
		return E('div', { 'class': 'cbi-section' }, [
			E('h3', {}, _('Installed Versions')),
			E('div', { 'class': 'cbi-section-descr' },
				_('Remote version checks are performed only when requested.')),
			E('div', { 'style': 'padding:8px 16px' }, [
				makeInfoRow(_('Installed'), status.installed_version
					? status.installed_version + (status.source_type ? ' (' + status.source_type + ')' : '')
					: '-'),
				makeInfoRow(_('Management Script'), scriptInfo.current || '-'),
				E('div', { 'style': 'margin-top:12px' }, [
					E('button', {
						'class': 'cbi-button cbi-button-action',
						'click': ui.createHandlerFn(this, 'handleCheckVersions')
					}, _('Check Remote Versions'))
				])
			])
		]);
	},

	renderScriptActions: function(scriptInfo) {
		return E('div', { 'class': 'cbi-section' }, [
			E('h3', {}, _('Management Script & LuCI Actions')),
			E('div', { 'style': 'padding:8px 16px' }, [
				makeInfoRow(_('Current Version'), scriptInfo.current || '-'),
				E('div', { 'style': 'margin-top:12px' }, [
					E('button', {
						'class': 'cbi-button cbi-button-action',
						'click': ui.createHandlerFn(this, 'handleCheckScriptUpdates')
					}, _('Check for Updates'))
				])
			])
		]);
	},

	renderUninstall: function() {
		return E('div', { 'class': 'cbi-section' }, [
			E('h3', {}, _('Uninstall')),
			E('div', { 'style': 'padding:12px 16px;border:1px solid #f1b0b7;background:#fff5f5;border-radius:4px' }, [
				E('p', { 'style': 'margin:0 0 12px;color:#666' },
					_('Remove Tailscale binaries, management scripts, and LuCI app files. The Tailscale state file will be preserved.')),
				E('button', {
					'class': 'cbi-button cbi-button-remove',
					'click': ui.createHandlerFn(this, 'handleUninstall')
				}, _('Uninstall Tailscale'))
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
			E('p', {}, _('Remote version check completed.')),
			E('div', { 'style': 'padding:4px 0 12px' }, [
				makeInfoRow(_('Installed'), currentVer),
				makeInfoRow(_('Current Source'), sourceType),
				makeInfoRow(_('Latest Official'), latestOfficial || '(check failed)'),
				makeInfoRow(_('Latest Small'), latestSmall || '(check failed)')
			]),
			updateAvailable
				? E('div', { 'style': 'margin:0 0 16px' }, [
					E('button', {
						'class': 'cbi-button cbi-button-apply',
						'click': function() {
							ui.hideModal();
							return self.handleUpdate();
						}
					}, _('Update Current Source to ') + currentLatest)
				])
				: E('p', { 'style': 'color:#666' }, _('Current source is up to date.')),
			E('div', { 'style': 'margin:16px 0 0;padding-top:12px;border-top:1px solid #eee' }, [
				E('strong', {}, _('Install specific official version')),
				E('div', { 'style': 'display:flex;gap:8px;align-items:center;margin-top:8px;flex-wrap:wrap' }, [
					officialSelect,
					E('button', {
						'class': 'cbi-button cbi-button-action',
						'click': function() {
							ui.hideModal();
							return self.handleInstallOfficialVersion();
						}
					}, _('Install Official'))
				])
			]),
			E('div', { 'style': 'margin:16px 0 0;padding-top:12px;border-top:1px solid #eee' }, [
				E('strong', {}, _('Install specific small version')),
				E('div', { 'style': 'display:flex;gap:8px;align-items:center;margin-top:8px;flex-wrap:wrap' }, [
					smallSelect,
					E('button', {
						'class': 'cbi-button cbi-button-action',
						'click': function() {
							ui.hideModal();
							return self.handleInstallSmallVersion();
						}
					}, _('Install Small'))
				])
			]),
			E('div', { 'class': 'right', 'style': 'margin-top:16px' }, [
				E('button', {
					'class': 'cbi-button',
					'click': ui.hideModal
				}, _('Close'))
			])
		];
	},

	renderScriptUpdateDialog: function(scriptInfo) {
		var self = this;
		var statusText = scriptInfo.latest
			? (scriptInfo.update_available ? _('Update available') : _('Up to Date'))
			: '(check failed)';
		var canUpgrade = !!(scriptInfo && scriptInfo.latest && scriptInfo.update_available);
		var buttonLabel = !scriptInfo.latest
			? _('Check Failed')
			: (scriptInfo.update_available ? _('Update Scripts & LuCI') : _('Up to Date'));

		return [
			E('div', { 'style': 'padding:4px 0 12px' }, [
				makeInfoRow(_('Current Version'), scriptInfo.current || '-'),
				makeInfoRow(_('Latest Version'), scriptInfo.latest || '(check failed)'),
				makeInfoRow(_('Status'), statusText)
			]),
			E('div', { 'class': 'right' }, [
				E('button', {
					'class': 'cbi-button',
					'click': ui.hideModal
				}, _('Close')),
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
		var m, s, o;

		m = new form.Map('tailscale', _('Tailscale Maintenance'),
			_('Manage update schedules, version control, and maintenance tasks.'));

		s = m.section(form.NamedSection, 'settings', 'tailscale', _('Tailscale Binary Auto-Update'));
		s.anonymous = false;
		s.addremove = false;

		o = s.option(form.Flag, 'auto_update', _('Enable'),
			_('Automatically check for and install Tailscale binary updates on schedule.'));
		o.default = '0';
		o.rmempty = false;

		o = s.option(form.Value, 'update_cron', _('Update Schedule'),
			_('Cron expression for binary update checks. Format: minute hour day month weekday.'));
		o.default = '30 3 * * *';
		o.placeholder = '30 3 * * *';
		o.depends('auto_update', '1');
		o.rmempty = false;
		o.validate = function(section_id, value) {
			if (!/^\s*(\S+\s+){4}\S+\s*$/.test(value))
				return _('Invalid cron expression. Expected 5 fields: minute hour day month weekday.');
			return true;
		};

		s = m.section(form.NamedSection, 'settings', 'tailscale', _('Management Script & LuCI Auto-Update'));
		s.anonymous = false;
		s.addremove = false;
		s.description = _('Updates the management script, helper libraries, and LuCI interface files. This does not update the Tailscale binary.');

		o = s.option(form.Flag, 'script_auto_update', _('Enable'),
			_('Automatically check for and install management script and LuCI app updates.'));
		o.default = '0';
		o.rmempty = false;

		o = s.option(form.Value, 'script_update_cron', _('Update Schedule'),
			_('Cron expression for script & LuCI update checks. Format: minute hour day month weekday.'));
		o.default = '0 4 * * 0';
		o.placeholder = '0 4 * * 0';
		o.depends('script_auto_update', '1');
		o.rmempty = false;
		o.validate = function(section_id, value) {
			if (!/^\s*(\S+\s+){4}\S+\s*$/.test(value))
				return _('Invalid cron expression. Expected 5 fields: minute hour day month weekday.');
			return true;
		};

		return m.render().then(L.bind(function(node) {
			var firstSection = node.querySelector('.cbi-section');
			if (firstSection)
				node.insertBefore(this.renderInstalledVersions(this.currentStatus, this.currentScriptInfo), firstSection);
			else
				node.appendChild(this.renderInstalledVersions(this.currentStatus, this.currentScriptInfo));

			node.appendChild(this.renderScriptActions(this.currentScriptInfo));
			node.appendChild(this.renderUninstall());
			return node;
		}, this));
	},

	handleCheckVersions: function() {
		ui.showModal(_('Checking Remote Versions'), [
			E('p', { 'class': 'spinning' }, _('Fetching remote version information...'))
		]);

		return Promise.all([
			L.resolveDefault(callGetLatestVersions(), {}),
			L.resolveDefault(callListVersions(20), {}),
			L.resolveDefault(callListOfficialVersions(20), {})
		]).then(L.bind(function(data) {
			ui.showModal(_('Tailscale Versions'),
				this.renderVersionDialog(this.currentStatus || {}, data[0] || {}, data[1] || {}, data[2] || {}));
		}, this)).catch(function(err) {
			ui.hideModal();
			ui.addNotification(null, E('p', {}, _('Failed to load remote versions: ') + err.message), 'danger');
		});
	},

	handleUpdate: function() {
		return handleAsyncTask(
			_('Updating Tailscale'),
			_('Downloading and installing the latest Tailscale binary...'),
			callDoUpdate(),
			_('Update successful. Reloading page...'),
			_('Update failed: '),
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
			ui.addNotification(null, E('p', {}, _('Please provide a version.')), 'warning');
			return;
		}

		return handleAsyncTask(
			_('Installing Tailscale v') + version,
			_('Downloading and installing version ') + version + ' (' + source + ')...',
			callDoInstallVersion(version, source),
			_('Successfully installed version ') + version + _('. Reloading page...'),
			_('Installation failed: '),
			true
		);
	},

	handleCheckScriptUpdates: function() {
		ui.showModal(_('Checking Script & LuCI Updates'), [
			E('p', { 'class': 'spinning' }, _('Checking remote script version...'))
		]);

		return callGetScriptUpdateInfo().then(L.bind(function(scriptInfo) {
			this.currentScriptInfo = scriptInfo || this.currentScriptInfo || {};
			ui.showModal(_('Script & LuCI Updates'), this.renderScriptUpdateDialog(this.currentScriptInfo));
		}, this)).catch(function(err) {
			ui.hideModal();
			ui.addNotification(null, E('p', {}, _('Failed to check script updates: ') + err.message), 'danger');
		});
	},

	handleUpgradeScripts: function(scriptInfo) {
		if (!scriptInfo || !scriptInfo.latest) {
			ui.addNotification(null, E('p', {}, _('Unable to determine the latest script version.')), 'warning');
			return Promise.resolve();
		}

		if (!scriptInfo.update_available) {
			ui.addNotification(null, E('p', {}, _('Scripts and LuCI files are already up to date.')), 'info');
			return Promise.resolve();
		}

		ui.showModal(_('Updating Scripts & LuCI'), [
			E('p', { 'class': 'spinning' }, _('Checking for updates and upgrading managed files...'))
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
			ui.addNotification(null, E('p', {}, _('RPC error: ') + err.message), 'danger');
		});
	},

	handleUpgradeScriptsResult: function(result) {
		var stdout = (result && result.stdout) || '';
		var alreadyCurrent = /Already up to date/i.test(stdout);

		ui.hideModal();

		if (result && result.code === 0) {
			if (alreadyCurrent) {
				ui.addNotification(null, E('p', {}, _('Scripts and LuCI files are already up to date.')), 'info');
				return;
			}

			ui.addNotification(null, E('p', {}, _('Scripts and LuCI files updated. Reloading page...')), 'info');
			window.setTimeout(function() { window.location.reload(); }, 2000);
			return;
		}

		ui.addNotification(null,
			E('p', {}, _('Script upgrade failed: ') + (stdout || 'Unknown error')),
			'danger');
	},

	handleUninstall: function() {
		ui.showModal(_('Confirm Uninstall'), [
			E('p', {}, _('This will remove Tailscale binaries, management scripts, and LuCI app files. The state file will be preserved.')),
			E('div', { 'class': 'right' }, [
				E('button', {
					'class': 'cbi-button',
					'click': ui.hideModal
				}, _('Cancel')),
				' ',
				E('button', {
					'class': 'cbi-button cbi-button-remove',
					'click': function() {
						ui.showModal(_('Uninstalling Tailscale'), [
							E('p', { 'class': 'spinning' }, _('Removing Tailscale...'))
						]);

						callDoUninstall().then(function(result) {
							ui.hideModal();
							if (result && result.code === 0) {
								ui.addNotification(null, E('p', {}, _('Tailscale uninstalled. Reloading page...')), 'info');
								window.setTimeout(function() { window.location.reload(); }, 2000);
							}
							else {
								ui.addNotification(null,
									E('p', {}, _('Uninstall failed: ') + ((result && result.stdout) || 'Unknown error')),
									'danger');
							}
						}).catch(function(err) {
							ui.hideModal();
							ui.addNotification(null, E('p', {}, _('RPC error: ') + err.message), 'danger');
						});
					}
				}, _('Uninstall'))
			])
		]);
	}
});
