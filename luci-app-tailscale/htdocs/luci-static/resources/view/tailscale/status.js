'use strict';
'require view';
'require dom';
'require poll';
'require rpc';
'require ui';

var callGetStatus = rpc.declare({
	object: 'luci.tailscale',
	method: 'get_status',
	expect: { '': {} }
});

var callGetInstallInfo = rpc.declare({
	object: 'luci.tailscale',
	method: 'get_install_info',
	expect: { '': {} }
});

var callGetLatestVersion = rpc.declare({
	object: 'luci.tailscale',
	method: 'get_latest_version',
	expect: { '': {} }
});

var callListVersions = rpc.declare({
	object: 'luci.tailscale',
	method: 'list_versions',
	params: ['limit'],
	expect: { '': {} }
});

var callServiceControl = rpc.declare({
	object: 'luci.tailscale',
	method: 'service_control',
	params: ['action']
});

var callDoInstall = rpc.declare({
	object: 'luci.tailscale',
	method: 'do_install',
	params: ['source', 'storage', 'auto_update']
});

var callDoInstallVersion = rpc.declare({
	object: 'luci.tailscale',
	method: 'do_install_version',
	params: ['version', 'source']
});

var callDoUpdate = rpc.declare({
	object: 'luci.tailscale',
	method: 'do_update'
});

var callDoUninstall = rpc.declare({
	object: 'luci.tailscale',
	method: 'do_uninstall'
});

var callSetupFirewall = rpc.declare({
	object: 'luci.tailscale',
	method: 'setup_firewall'
});

var callSyncScripts = rpc.declare({
	object: 'luci.tailscale',
	method: 'sync_scripts'
});

function formatBytes(bytes) {
	if (bytes == null || bytes === 0) return '0 B';
	var k = 1024;
	var sizes = ['B', 'KB', 'MB', 'GB'];
	var i = Math.floor(Math.log(bytes) / Math.log(k));
	return parseFloat((bytes / Math.pow(k, i)).toFixed(1)) + ' ' + sizes[i];
}

function formatLastSeen(ts) {
	if (!ts) return '-';
	var diff = Math.floor((Date.now() - new Date(ts).getTime()) / 1000);
	if (diff < 0) return '-';
	if (diff < 60) return diff + 's ago';
	if (diff < 3600) return Math.floor(diff / 60) + 'm ago';
	if (diff < 86400) return Math.floor(diff / 3600) + 'h ago';
	return Math.floor(diff / 86400) + 'd ago';
}

function statusIndicator(running) {
	return E('span', {
		'style': 'font-weight:bold;color:' + (running ? '#4caf50' : '#f44336')
	}, (running ? '\u25cf ' : '\u25cf ') + (running ? _('Running') : _('Stopped')));
}

function makeInfoRow(label, value) {
	return E('div', { 'style': 'display:flex;padding:4px 0' }, [
		E('span', { 'style': 'min-width:160px;font-weight:bold;color:#666' }, label),
		E('span', {}, value || '-')
	]);
}

return view.extend({
	statusElements: {},
	currentStatus: null,

	load: function() {
		return Promise.all([
			L.resolveDefault(callGetStatus(), {}),
			L.resolveDefault(callGetInstallInfo(), {}),
			L.resolveDefault(callGetLatestVersion(), {}),
			L.resolveDefault(callListVersions(20), {})
		]);
	},

	render: function(data) {
		var status = data[0] || {};
		var installInfo = data[1] || {};
		var latestInfo = data[2] || {};
		var versionList = data[3] || {};

		this.currentStatus = status;

		var container = E('div', { 'class': 'cbi-map' }, [
			E('h2', {}, _('Tailscale')),
			E('div', { 'class': 'cbi-map-descr' }, _('Tailscale VPN status and management.'))
		]);

		if (!status.installed) {
			container.appendChild(this.renderInstallWizard(installInfo));
		} else {
			container.appendChild(this.renderServiceStatus(status));

			if (status.running && status.backend_state === 'NeedsLogin') {
				container.appendChild(this.renderNeedsLogin());
			} else if (status.running && status.peers) {
				container.appendChild(this.renderPeerTable(status));
			}

			container.appendChild(this.renderServiceControl(status));
			container.appendChild(this.renderVersionManagement(status, latestInfo, versionList));
			container.appendChild(this.renderSubnetRouting());
			container.appendChild(this.renderMaintenance());
		}

		poll.add(L.bind(this.pollStatus, this), 10);

		return container;
	},

	pollStatus: function() {
		var self = this;
		return callGetStatus().then(function(status) {
			if (!status) return;

			var wasInstalled = self.currentStatus && self.currentStatus.installed;
			var isInstalled = status.installed;
			if (wasInstalled !== isInstalled) {
				window.location.reload();
				return;
			}

			self.currentStatus = status;
			self.updateStatusDisplay(status);
		});
	},

	updateStatusDisplay: function(status) {
		var el = this.statusElements;

		if (el.running)
			dom.content(el.running, statusIndicator(status.running));
		if (el.pid)
			dom.content(el.pid, status.pid ? String(status.pid) : '-');
		if (el.version)
			dom.content(el.version, status.installed_version
				? status.installed_version + (status.source_type ? ' (' + status.source_type + ')' : '')
				: '-');
		if (el.tunMode)
			dom.content(el.tunMode, status.tun_mode || '-');
		if (el.backendState)
			dom.content(el.backendState, status.backend_state || '-');
		if (el.ips)
			dom.content(el.ips, (status.tailscale_ips && status.tailscale_ips.length)
				? status.tailscale_ips.join(', ') : '-');
		if (el.hostname)
			dom.content(el.hostname, status.hostname || '-');

		if (el.peerTableBody && status.peers) {
			this.updatePeerTableBody(el.peerTableBody, status.peers);
		}
	},

	/* ================================================================
	 * Install Wizard (Phase 2)
	 * ================================================================ */

	renderInstallWizard: function(installInfo) {
		var sourceSelect = E('select', { 'class': 'cbi-input-select', 'id': 'ts-install-source' }, [
			E('option', { 'value': 'small', 'selected': 'selected' },
				_('Small (Compressed, ~10MB) — Recommended')),
			E('option', { 'value': 'official' },
				_('Official (~50MB)'))
		]);

		var storageSelect = E('select', { 'class': 'cbi-input-select', 'id': 'ts-install-storage' }, [
			E('option', { 'value': 'persistent', 'selected': 'selected' },
				_('Persistent (/opt/tailscale)')),
			E('option', { 'value': 'ram' },
				_('RAM (/tmp/tailscale) — re-downloads on boot'))
		]);

		var autoUpdateCheck = E('input', {
			'type': 'checkbox',
			'id': 'ts-install-autoupdate',
			'checked': 'checked'
		});

		return E('div', { 'class': 'cbi-section' }, [
			E('h3', {}, _('Install Tailscale')),
			E('div', { 'class': 'cbi-section-descr' },
				_('Tailscale is not installed on this device. Configure the options below and click Install.')),

			E('div', { 'class': 'cbi-value' }, [
				E('label', { 'class': 'cbi-value-title' }, _('Architecture')),
				E('div', { 'class': 'cbi-value-field' },
					E('em', {}, installInfo.arch || _('detecting...')))
			]),
			E('div', { 'class': 'cbi-value' }, [
				E('label', { 'class': 'cbi-value-title' }, _('Download Source')),
				E('div', { 'class': 'cbi-value-field' }, sourceSelect)
			]),
			E('div', { 'class': 'cbi-value' }, [
				E('label', { 'class': 'cbi-value-title' }, _('Storage Mode')),
				E('div', { 'class': 'cbi-value-field' }, storageSelect)
			]),
			E('div', { 'class': 'cbi-value' }, [
				E('label', { 'class': 'cbi-value-title' }, _('Auto Update')),
				E('div', { 'class': 'cbi-value-field' }, [
					autoUpdateCheck,
					E('span', { 'style': 'margin-left:8px' },
						_('Check for updates daily at 3:30 AM'))
				])
			]),

			E('div', { 'class': 'cbi-page-actions' }, [
				E('button', {
					'class': 'cbi-button cbi-button-apply',
					'click': ui.createHandlerFn(this, 'handleInstall')
				}, _('Install Tailscale'))
			])
		]);
	},

	handleInstall: function() {
		var source = document.getElementById('ts-install-source').value;
		var storage = document.getElementById('ts-install-storage').value;
		var autoUpdate = document.getElementById('ts-install-autoupdate').checked ? '1' : '0';

		ui.showModal(_('Installing Tailscale'), [
			E('p', { 'class': 'spinning' },
				_('Downloading and installing Tailscale. This may take a few minutes...'))
		]);

		return callDoInstall(source, storage, autoUpdate).then(function(result) {
			ui.hideModal();
			if (result && result.code === 0) {
				ui.addNotification(null,
					E('p', {}, _('Tailscale installed successfully. Reloading page...')), 'info');
				window.setTimeout(function() { window.location.reload(); }, 2000);
			} else {
				ui.addNotification(null,
					E('p', {}, _('Installation failed: ') + ((result && result.stdout) || _('Unknown error'))),
					'danger');
			}
		}).catch(function(err) {
			ui.hideModal();
			ui.addNotification(null,
				E('p', {}, _('RPC error: ') + err.message), 'danger');
		});
	},

	/* ================================================================
	 * Service Status (Phase 2)
	 * ================================================================ */

	renderServiceStatus: function(status) {
		var el = this.statusElements;

		el.running = E('span');
		el.pid = E('span');
		el.version = E('span');
		el.tunMode = E('span');
		el.backendState = E('span');
		el.ips = E('span');
		el.hostname = E('span');

		dom.content(el.running, statusIndicator(status.running));
		dom.content(el.pid, status.pid ? String(status.pid) : '-');
		dom.content(el.version, status.installed_version
			? status.installed_version + (status.source_type ? ' (' + status.source_type + ')' : '')
			: '-');
		dom.content(el.tunMode, status.tun_mode || '-');
		dom.content(el.backendState, status.backend_state || '-');
		dom.content(el.ips, (status.tailscale_ips && status.tailscale_ips.length)
			? status.tailscale_ips.join(', ') : '-');
		dom.content(el.hostname, status.hostname || '-');

		return E('div', { 'class': 'cbi-section' }, [
			E('h3', {}, _('Service Status')),
			E('div', { 'style': 'padding:8px 16px' }, [
				makeInfoRow(_('Status'), el.running),
				makeInfoRow(_('PID'), el.pid),
				makeInfoRow(_('Version'), el.version),
				makeInfoRow(_('TUN Mode'), el.tunMode),
				makeInfoRow(_('Backend State'), el.backendState),
				makeInfoRow(_('Tailscale IPs'), el.ips),
				makeInfoRow(_('Hostname'), el.hostname)
			])
		]);
	},

	renderNeedsLogin: function() {
		return E('div', { 'class': 'cbi-section' }, [
			E('h3', {}, _('Authentication Required')),
			E('div', {
				'class': 'alert-message warning',
				'style': 'padding:12px 16px;background:#fff3cd;border:1px solid #ffc107;border-radius:4px'
			}, [
				E('p', { 'style': 'margin:0' }, [
					E('strong', {}, _('Tailscale needs authentication.')),
					E('br'),
					_('Please run the following command via SSH to complete login:')
				]),
				E('pre', { 'style': 'margin:8px 0 0;padding:8px;background:#f8f9fa;border-radius:4px' },
					'tailscale up')
			])
		]);
	},

	/* ================================================================
	 * Peer Table (Phase 2)
	 * ================================================================ */

	renderPeerTable: function(status) {
		var tbody = E('tbody');
		this.statusElements.peerTableBody = tbody;
		this.updatePeerTableBody(tbody, status.peers || []);

		return E('div', { 'class': 'cbi-section' }, [
			E('h3', {}, _('Connected Peers')),
			E('table', { 'class': 'table', 'style': 'width:100%' }, [
				E('thead', {}, [
					E('tr', { 'class': 'tr table-titles' }, [
						E('th', { 'class': 'th' }, _('Hostname')),
						E('th', { 'class': 'th' }, _('IP')),
						E('th', { 'class': 'th' }, _('OS')),
						E('th', { 'class': 'th' }, _('Status')),
						E('th', { 'class': 'th' }, _('Exit Node')),
						E('th', { 'class': 'th' }, _('Traffic')),
						E('th', { 'class': 'th' }, _('Last Seen'))
					])
				]),
				tbody
			])
		]);
	},

	updatePeerTableBody: function(tbody, peers) {
		dom.content(tbody, null);

		if (!peers || peers.length === 0) {
			tbody.appendChild(
				E('tr', { 'class': 'tr placeholder' }, [
					E('td', { 'class': 'td', 'colspan': '7', 'style': 'text-align:center;color:#999' },
						_('No peers connected'))
				])
			);
			return;
		}

		var sorted = peers.slice().sort(function(a, b) {
			if (a.online === b.online) return (a.hostname || '').localeCompare(b.hostname || '');
			return a.online ? -1 : 1;
		});

		for (var i = 0; i < sorted.length; i++) {
			var p = sorted[i];
			var traffic = '';
			if (p.rx_bytes != null || p.tx_bytes != null) {
				traffic = '\u2191' + formatBytes(p.tx_bytes) + ' \u2193' + formatBytes(p.rx_bytes);
			}

			tbody.appendChild(
				E('tr', { 'class': 'tr' }, [
					E('td', { 'class': 'td' }, p.hostname || '-'),
					E('td', { 'class': 'td' }, p.ip || '-'),
					E('td', { 'class': 'td' }, p.os || '-'),
					E('td', { 'class': 'td' },
						E('span', {
							'style': 'color:' + (p.online ? '#4caf50' : '#999')
						}, p.online ? _('Online') : _('Offline'))),
					E('td', { 'class': 'td' }, p.exit_node ? _('Yes') : '-'),
					E('td', { 'class': 'td' }, traffic || '-'),
					E('td', { 'class': 'td' }, p.online ? '-' : formatLastSeen(p.last_seen))
				])
			);
		}
	},

	/* ================================================================
	 * Service Control (Phase 3)
	 * ================================================================ */

	renderServiceControl: function(status) {
		return E('div', { 'class': 'cbi-section' }, [
			E('h3', {}, _('Service Control')),
			E('div', { 'style': 'display:flex;gap:8px;padding:8px 16px;flex-wrap:wrap' }, [
				E('button', {
					'class': 'cbi-button cbi-button-apply',
					'click': ui.createHandlerFn(this, 'handleServiceAction', 'start'),
					'disabled': status.running ? 'disabled' : null
				}, _('Start')),
				E('button', {
					'class': 'cbi-button cbi-button-reset',
					'click': ui.createHandlerFn(this, 'handleServiceAction', 'stop'),
					'disabled': !status.running ? 'disabled' : null
				}, _('Stop')),
				E('button', {
					'class': 'cbi-button cbi-button-save',
					'click': ui.createHandlerFn(this, 'handleServiceAction', 'restart')
				}, _('Restart'))
			])
		]);
	},

	handleServiceAction: function(ev, action) {
		return callServiceControl(action).then(function(result) {
			if (result && result.code === 0) {
				ui.addNotification(null,
					E('p', {}, _('Service %s completed.').format(action)), 'info');
			} else {
				ui.addNotification(null,
					E('p', {}, _('Service %s failed: ').format(action) +
						((result && result.stdout) || _('Unknown error'))), 'danger');
			}
		});
	},

	/* ================================================================
	 * Version Management (Phase 3)
	 * ================================================================ */

	renderVersionManagement: function(status, latestInfo, versionList) {
		var currentVer = status.installed_version || '-';
		var sourceType = status.source_type || 'official';
		var latestVer = (latestInfo && latestInfo.version) ? latestInfo.version : null;
		var versions = (versionList && versionList.versions) ? versionList.versions : [];

		var updateAvailable = latestVer && currentVer !== '-' && latestVer !== currentVer;

		var versionSelect = E('select', { 'class': 'cbi-input-select', 'id': 'ts-target-version' });
		for (var i = 0; i < versions.length; i++) {
			versionSelect.appendChild(
				E('option', { 'value': versions[i] }, versions[i])
			);
		}
		if (versions.length === 0) {
			versionSelect.appendChild(
				E('option', { 'value': '' }, _('(no versions available)'))
			);
		}

		var sourceSelect = E('select', { 'class': 'cbi-input-select', 'id': 'ts-target-source' }, [
			E('option', { 'value': 'small', 'selected': sourceType === 'small' ? 'selected' : null },
				_('Small')),
			E('option', { 'value': 'official', 'selected': sourceType === 'official' ? 'selected' : null },
				_('Official'))
		]);

		var children = [
			E('h3', {}, _('Version Management')),
			E('div', { 'style': 'padding:8px 16px' }, [
				makeInfoRow(_('Installed'), currentVer + ' (' + sourceType + ')'),
				makeInfoRow(_('Latest'),
					latestVer
						? (latestVer + (updateAvailable ? ' \u2014 ' + _('update available') : ''))
						: _('(checking...)')),

				updateAvailable
					? E('div', { 'style': 'margin:12px 0' }, [
						E('button', {
							'class': 'cbi-button cbi-button-apply',
							'click': ui.createHandlerFn(this, 'handleUpdate')
						}, _('Update to %s').format(latestVer))
					])
					: E('div'),

				E('div', { 'style': 'margin:16px 0 0;padding-top:12px;border-top:1px solid #eee' }, [
					E('strong', {}, _('Install specific version')),
					E('div', { 'style': 'display:flex;gap:8px;align-items:center;margin-top:8px;flex-wrap:wrap' }, [
						versionSelect,
						sourceSelect,
						E('button', {
							'class': 'cbi-button cbi-button-action',
							'click': ui.createHandlerFn(this, 'handleInstallVersion')
						}, _('Install'))
					])
				])
			])
		];

		return E('div', { 'class': 'cbi-section' }, children);
	},

	handleUpdate: function() {
		ui.showModal(_('Updating Tailscale'), [
			E('p', { 'class': 'spinning' }, _('Downloading and installing the latest version...'))
		]);

		return callDoUpdate().then(function(result) {
			ui.hideModal();
			if (result && result.code === 0) {
				ui.addNotification(null, E('p', {}, _('Update successful!')), 'info');
			} else {
				ui.addNotification(null,
					E('p', {}, _('Update failed: ') + ((result && result.stdout) || _('Unknown error'))),
					'danger');
			}
		}).catch(function(err) {
			ui.hideModal();
			ui.addNotification(null, E('p', {}, _('RPC error: ') + err.message), 'danger');
		});
	},

	handleInstallVersion: function() {
		var version = document.getElementById('ts-target-version').value;
		var source = document.getElementById('ts-target-source').value;

		if (!version) {
			ui.addNotification(null, E('p', {}, _('Please select a version.')), 'warning');
			return;
		}

		ui.showModal(_('Installing Tailscale v%s').format(version), [
			E('p', { 'class': 'spinning' },
				_('Downloading and installing version %s (%s)...').format(version, source))
		]);

		return callDoInstallVersion(version, source).then(function(result) {
			ui.hideModal();
			if (result && result.code === 0) {
				ui.addNotification(null,
					E('p', {}, _('Successfully installed version %s.').format(version)), 'info');
			} else {
				ui.addNotification(null,
					E('p', {}, _('Installation failed: ') + ((result && result.stdout) || _('Unknown error'))),
					'danger');
			}
		}).catch(function(err) {
			ui.hideModal();
			ui.addNotification(null, E('p', {}, _('RPC error: ') + err.message), 'danger');
		});
	},

	/* ================================================================
	 * Subnet Routing (Phase 3)
	 * ================================================================ */

	renderSubnetRouting: function() {
		return E('div', { 'class': 'cbi-section' }, [
			E('h3', {}, _('Subnet Routing')),
			E('div', { 'style': 'padding:8px 16px' }, [
				E('p', { 'style': 'margin:0 0 8px;color:#666' },
					_('Create the OpenWrt network interface and firewall zone for Tailscale subnet routing.')),
				E('button', {
					'class': 'cbi-button cbi-button-action',
					'click': ui.createHandlerFn(this, 'handleSetupFirewall')
				}, _('Configure Network Interface & Firewall'))
			])
		]);
	},

	handleSetupFirewall: function() {
		ui.showModal(_('Configuring Subnet Routing'), [
			E('p', { 'class': 'spinning' },
				_('Creating network interface and firewall zone...'))
		]);

		return callSetupFirewall().then(function(result) {
			ui.hideModal();
			if (result && result.success) {
				ui.addNotification(null,
					E('p', {}, _('Network interface and firewall zone configured successfully.')), 'info');
			} else {
				ui.addNotification(null,
					E('p', {}, _('Configuration failed: ') + ((result && result.stdout) || _('Unknown error'))),
					'danger');
			}
		}).catch(function(err) {
			ui.hideModal();
			ui.addNotification(null, E('p', {}, _('RPC error: ') + err.message), 'danger');
		});
	},

	/* ================================================================
	 * Maintenance (Phase 3)
	 * ================================================================ */

	renderMaintenance: function() {
		return E('div', { 'class': 'cbi-section' }, [
			E('h3', {}, _('Maintenance')),
			E('div', { 'style': 'display:flex;gap:8px;padding:8px 16px;flex-wrap:wrap' }, [
				E('button', {
					'class': 'cbi-button cbi-button-action',
					'click': ui.createHandlerFn(this, 'handleSyncScripts')
				}, _('Sync Scripts')),
				E('button', {
					'class': 'cbi-button cbi-button-remove',
					'click': ui.createHandlerFn(this, 'handleUninstall')
				}, _('Uninstall Tailscale'))
			])
		]);
	},

	handleSyncScripts: function() {
		ui.showModal(_('Syncing Scripts'), [
			E('p', { 'class': 'spinning' }, _('Downloading and updating managed scripts...'))
		]);

		return callSyncScripts().then(function(result) {
			ui.hideModal();
			if (result && result.code === 0) {
				ui.addNotification(null, E('p', {}, _('Scripts synced successfully.')), 'info');
			} else {
				ui.addNotification(null,
					E('p', {}, _('Sync failed: ') + ((result && result.stdout) || _('Unknown error'))),
					'danger');
			}
		}).catch(function(err) {
			ui.hideModal();
			ui.addNotification(null, E('p', {}, _('RPC error: ') + err.message), 'danger');
		});
	},

	handleUninstall: function() {
		var self = this;
		ui.showModal(_('Confirm Uninstall'), [
			E('p', {},
				_('This will remove Tailscale binaries, scripts, configuration, and LuCI app files. ' +
				  'The state file will be preserved.')),
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
								ui.addNotification(null,
									E('p', {}, _('Tailscale uninstalled. Reloading page...')), 'info');
								window.setTimeout(function() { window.location.reload(); }, 2000);
							} else {
								ui.addNotification(null,
									E('p', {}, _('Uninstall failed: ') +
										((result && result.stdout) || _('Unknown error'))), 'danger');
							}
						}).catch(function(err) {
							ui.hideModal();
							ui.addNotification(null,
								E('p', {}, _('RPC error: ') + err.message), 'danger');
						});
					}
				}, _('Uninstall'))
			])
		]);
	},

	handleSaveApply: null,
	handleSave: null,
	handleReset: null
});
