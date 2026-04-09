'use strict';
'require view';
'require dom';
'require poll';
'require rpc';
'require ui';

var _ = function(s) { return s; };

var callGetStatus = rpc.declare({
	object: 'luci-tailscale',
	method: 'get_status',
	expect: { '': {} }
});

var callGetInstallInfo = rpc.declare({
	object: 'luci-tailscale',
	method: 'get_install_info',
	expect: { '': {} }
});

var callServiceControl = rpc.declare({
	object: 'luci-tailscale',
	method: 'service_control',
	params: ['action']
});

var callDoInstall = rpc.declare({
	object: 'luci-tailscale',
	method: 'do_install',
	params: ['source', 'storage', 'auto_update']
});

var callGetTaskStatus = rpc.declare({
	object: 'luci-tailscale',
	method: 'get_task_status',
	params: ['task'],
	expect: { '': {} }
});

function formatBytes(bytes) {
	if (bytes == null || bytes === 0)
		return '0 B';

	var k = 1024;
	var sizes = ['B', 'KB', 'MB', 'GB'];
	var i = Math.floor(Math.log(bytes) / Math.log(k));
	return parseFloat((bytes / Math.pow(k, i)).toFixed(1)) + ' ' + sizes[i];
}

function formatLastSeen(ts) {
	if (!ts)
		return '-';

	var diff = Math.floor((Date.now() - new Date(ts).getTime()) / 1000);
	if (diff < 0)
		return '-';
	if (diff < 60)
		return diff + 's ago';
	if (diff < 3600)
		return Math.floor(diff / 60) + 'm ago';
	if (diff < 86400)
		return Math.floor(diff / 3600) + 'h ago';
	return Math.floor(diff / 86400) + 'd ago';
}

function statusIndicator(running) {
	return E('span', {
		'style': 'font-weight:bold;color:' + (running ? '#4caf50' : '#f44336')
	}, (running ? '\u25cf ' : '\u25cf ') + (running ? 'Running' : 'Stopped'));
}

function makeInfoRow(label, value) {
	return E('div', { 'style': 'display:flex;padding:4px 0' }, [
		E('span', { 'style': 'min-width:160px;font-weight:bold;color:#666' }, label),
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

return view.extend({
	statusElements: {},
	currentStatus: null,

	load: function() {
		return Promise.all([
			L.resolveDefault(callGetStatus(), {}),
			L.resolveDefault(callGetInstallInfo(), {})
		]);
	},

	render: function(data) {
		var status = data[0] || {};
		var installInfo = data[1] || {};

		this.currentStatus = status;

		var container = E('div', { 'class': 'cbi-map' }, [
			E('h2', {}, 'Tailscale'),
			E('div', { 'class': 'cbi-map-descr' }, 'Tailscale VPN status and management.')
		]);

		if (!status.installed) {
			container.appendChild(this.renderInstallWizard(installInfo));
		}
		else {
			container.appendChild(this.renderServiceControl(status));
			container.appendChild(this.renderServiceStatus(status));

			if (status.running && status.backend_state === 'NeedsLogin')
				container.appendChild(this.renderNeedsLogin());
			else if (status.running && status.peers)
				container.appendChild(this.renderPeerTable(status));
		}

		poll.add(L.bind(this.pollStatus, this), 10);

		return container;
	},

	pollStatus: function() {
		var self = this;
		return callGetStatus().then(function(status) {
			if (!status)
				return;

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
		if (el.deviceName)
			dom.content(el.deviceName, status.device_name || '-');

		if (el.peerTableBody && status.peers)
			this.updatePeerTableBody(el.peerTableBody, status.peers);
	},

	renderInstallWizard: function(installInfo) {
		var sourceSelect = E('select', { 'class': 'cbi-input-select', 'id': 'ts-install-source' }, [
			E('option', { 'value': 'small', 'selected': 'selected' }, 'Small (Compressed, ~10MB) - Recommended'),
			E('option', { 'value': 'official' }, 'Official (~50MB)')
		]);

		var storageSelect = E('select', { 'class': 'cbi-input-select', 'id': 'ts-install-storage' }, [
			E('option', { 'value': 'persistent', 'selected': 'selected' }, 'Persistent (/opt/tailscale)'),
			E('option', { 'value': 'ram' }, 'RAM (/tmp/tailscale) - re-downloads on boot')
		]);

		var autoUpdateCheck = E('input', {
			'type': 'checkbox',
			'id': 'ts-install-autoupdate',
			'checked': 'checked'
		});

		return E('div', { 'class': 'cbi-section' }, [
			E('h3', {}, 'Install Tailscale'),
			E('div', { 'class': 'cbi-section-descr' },
				'Tailscale is not installed on this device. Configure the options below and click Install.'),
			E('div', { 'class': 'cbi-value' }, [
				E('label', { 'class': 'cbi-value-title' }, 'Architecture'),
				E('div', { 'class': 'cbi-value-field' }, E('em', {}, installInfo.arch || 'detecting...'))
			]),
			E('div', { 'class': 'cbi-value' }, [
				E('label', { 'class': 'cbi-value-title' }, 'Download Source'),
				E('div', { 'class': 'cbi-value-field' }, sourceSelect)
			]),
			E('div', { 'class': 'cbi-value' }, [
				E('label', { 'class': 'cbi-value-title' }, 'Storage Mode'),
				E('div', { 'class': 'cbi-value-field' }, storageSelect)
			]),
			E('div', { 'class': 'cbi-value' }, [
				E('label', { 'class': 'cbi-value-title' }, 'Auto Update'),
				E('div', { 'class': 'cbi-value-field' }, [
					autoUpdateCheck,
					E('span', { 'style': 'margin-left:8px' }, 'Check for updates daily at 3:30 AM')
				])
			]),
			E('div', { 'class': 'cbi-page-actions' }, [
				E('button', {
					'class': 'cbi-button cbi-button-apply',
					'click': ui.createHandlerFn(this, 'handleInstall')
				}, 'Install Tailscale')
			])
		]);
	},

	handleInstall: function() {
		var source = document.getElementById('ts-install-source').value;
		var storage = document.getElementById('ts-install-storage').value;
		var autoUpdate = document.getElementById('ts-install-autoupdate').checked ? '1' : '0';

		ui.showModal('Installing Tailscale', [
			E('p', { 'class': 'spinning' }, 'Downloading and installing Tailscale. This may take a few minutes...')
		]);

		return callDoInstall(source, storage, autoUpdate).then(function(result) {
			if (result && result.started && result.task) {
				return pollTaskStatus(result.task).then(function(status) {
					ui.hideModal();
					if (status && status.code === 0) {
						ui.addNotification(null, E('p', {}, 'Tailscale installed successfully. Reloading page...'), 'info');
						window.setTimeout(function() { window.location.reload(); }, 2000);
					}
					else {
						ui.addNotification(null,
							E('p', {}, 'Installation failed: ' + ((status && status.stdout) || 'Unknown error')),
							'danger');
					}
				});
			}

			ui.hideModal();
			if (result && result.code === 0) {
				ui.addNotification(null, E('p', {}, 'Tailscale installed successfully. Reloading page...'), 'info');
				window.setTimeout(function() { window.location.reload(); }, 2000);
			}
			else {
				ui.addNotification(null,
					E('p', {}, 'Installation failed: ' + ((result && result.stdout) || 'Unknown error')),
					'danger');
			}
		}).catch(function(err) {
			ui.hideModal();
			ui.addNotification(null, E('p', {}, 'RPC error: ' + err.message), 'danger');
		});
	},

	renderServiceStatus: function(status) {
		var el = this.statusElements;

		el.running = E('span');
		el.pid = E('span');
		el.version = E('span');
		el.tunMode = E('span');
		el.backendState = E('span');
		el.ips = E('span');
		el.deviceName = E('span');

		dom.content(el.running, statusIndicator(status.running));
		dom.content(el.pid, status.pid ? String(status.pid) : '-');
		dom.content(el.version, status.installed_version
			? status.installed_version + (status.source_type ? ' (' + status.source_type + ')' : '')
			: '-');
		dom.content(el.tunMode, status.tun_mode || '-');
		dom.content(el.backendState, status.backend_state || '-');
		dom.content(el.ips, (status.tailscale_ips && status.tailscale_ips.length)
			? status.tailscale_ips.join(', ') : '-');
		dom.content(el.deviceName, status.device_name || '-');

		return E('div', { 'class': 'cbi-section' }, [
			E('h3', {}, 'Service Status'),
			E('div', { 'style': 'padding:8px 16px' }, [
				makeInfoRow('Status', el.running),
				makeInfoRow('Device Name', el.deviceName),
				makeInfoRow('PID', el.pid),
				makeInfoRow('Version', el.version),
				makeInfoRow('Network Mode', el.tunMode),
				makeInfoRow('Backend State', el.backendState),
				makeInfoRow('Tailscale IPs', el.ips)
			])
		]);
	},

	renderNeedsLogin: function() {
		return E('div', { 'class': 'cbi-section' }, [
			E('h3', {}, 'Authentication Required'),
			E('div', {
				'class': 'alert-message warning',
				'style': 'padding:12px 16px;background:#fff3cd;border:1px solid #ffc107;border-radius:4px'
			}, [
				E('p', { 'style': 'margin:0' }, [
					E('strong', {}, 'Tailscale needs authentication.'),
					E('br'),
					'Please run the following command via SSH to complete login:'
				]),
				E('pre', { 'style': 'margin:8px 0 0;padding:8px;background:#f8f9fa;border-radius:4px' },
					'tailscale up')
			])
		]);
	},

	renderPeerTable: function(status) {
		var tbody = E('tbody');
		this.statusElements.peerTableBody = tbody;
		this.updatePeerTableBody(tbody, status.peers || []);

		return E('div', { 'class': 'cbi-section' }, [
			E('h3', {}, 'Connected Devices'),
			E('table', { 'class': 'table', 'style': 'width:100%' }, [
				E('thead', {}, [
					E('tr', { 'class': 'tr table-titles' }, [
						E('th', { 'class': 'th' }, 'Name'),
						E('th', { 'class': 'th' }, 'IP'),
						E('th', { 'class': 'th' }, 'OS'),
						E('th', { 'class': 'th' }, 'Status'),
						E('th', { 'class': 'th' }, 'Exit Node'),
						E('th', { 'class': 'th' }, 'Traffic'),
						E('th', { 'class': 'th' }, 'Last Seen')
					])
				]),
				tbody
			])
		]);
	},

	updatePeerTableBody: function(tbody, peers) {
		dom.content(tbody, null);

		if (!peers || peers.length === 0) {
			tbody.appendChild(E('tr', { 'class': 'tr placeholder' }, [
				E('td', { 'class': 'td', 'colspan': '7', 'style': 'text-align:center;color:#999' }, 'No peers connected')
			]));
			return;
		}

		var sorted = peers.slice().sort(function(a, b) {
			if (a.online === b.online)
				return (a.name || a.dns_name || '').localeCompare(b.name || b.dns_name || '');
			return a.online ? -1 : 1;
		});

		for (var i = 0; i < sorted.length; i++) {
			var p = sorted[i];
			var traffic = '';
			if (p.rx_bytes != null || p.tx_bytes != null)
				traffic = '\u2191' + formatBytes(p.tx_bytes) + ' \u2193' + formatBytes(p.rx_bytes);

			tbody.appendChild(E('tr', { 'class': 'tr' }, [
				E('td', { 'class': 'td' }, [
					p.name || '-',
					p.self ? E('div', { 'style': 'font-size:11px;color:#666;margin-top:2px' }, 'This device') : null
				]),
				E('td', { 'class': 'td' }, p.ip || '-'),
				E('td', { 'class': 'td' }, p.os || '-'),
				E('td', { 'class': 'td' },
					E('span', {
						'style': 'color:' + (p.online ? '#4caf50' : '#999')
					}, p.online ? 'Online' : 'Offline')),
				E('td', { 'class': 'td' }, p.exit_node ? 'Yes' : '-'),
				E('td', { 'class': 'td' }, traffic || '-'),
				E('td', { 'class': 'td' }, p.online ? '-' : formatLastSeen(p.last_seen))
			]));
		}
	},

	renderServiceControl: function(status) {
		return E('div', { 'class': 'cbi-section' }, [
			E('h3', {}, 'Service Control'),
			E('div', { 'style': 'display:flex;gap:8px;padding:8px 16px;flex-wrap:wrap' }, [
				E('button', {
					'class': 'cbi-button cbi-button-apply',
					'click': ui.createHandlerFn(this, 'handleServiceAction', 'start'),
					'disabled': status.running ? 'disabled' : null
				}, 'Start'),
				E('button', {
					'class': 'cbi-button cbi-button-reset',
					'click': ui.createHandlerFn(this, 'handleServiceAction', 'stop'),
					'disabled': !status.running ? 'disabled' : null
				}, 'Stop'),
				E('button', {
					'class': 'cbi-button cbi-button-save',
					'click': ui.createHandlerFn(this, 'handleServiceAction', 'restart')
				}, 'Restart')
			])
		]);
	},

	handleServiceAction: function(ev, action) {
		return callServiceControl(action).then(function(result) {
			if (result && result.code === 0)
				ui.addNotification(null, E('p', {}, 'Service ' + action + ' completed.'), 'info');
			else
				ui.addNotification(null,
					E('p', {}, 'Service ' + action + ' failed: ' + ((result && result.stdout) || 'Unknown error')),
					'danger');
		});
	},

	handleSaveApply: null,
	handleSave: null,
	handleReset: null
});
