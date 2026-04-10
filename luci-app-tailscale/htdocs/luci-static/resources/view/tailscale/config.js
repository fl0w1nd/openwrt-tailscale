'use strict';
'require view';
'require form';
'require uci';
'require rpc';
'require ui';

var _ = function(s) { return s; };

var callGetInstallInfo = rpc.declare({
	object: 'luci-tailscale',
	method: 'get_install_info',
	expect: { '': {} }
});

var callSetupFirewall = rpc.declare({
	object: 'luci-tailscale',
	method: 'setup_firewall'
});

function makeInfoRow(label, value) {
	return E('div', { 'style': 'display:flex;padding:4px 0' }, [
		E('span', { 'style': 'min-width:180px;font-weight:bold;color:#666' }, label),
		E('span', {}, value || '-')
	]);
}

return view.extend({
	load: function() {
		return Promise.all([
			uci.load('tailscale'),
			L.resolveDefault(callGetInstallInfo(), {})
		]);
	},

	renderInstallationInfo: function(installInfo) {
		var storageMode = uci.get('tailscale', 'settings', 'storage_mode') || 'N/A';
		var downloadSource = installInfo.source || uci.get('tailscale', 'settings', 'download_source') || 'N/A';
		var binDir = installInfo.bin_dir || uci.get('tailscale', 'settings', 'bin_dir') || 'N/A';
		var version = installInfo.version || 'N/A';
		var arch = installInfo.arch || 'N/A';

		return E('div', { 'class': 'cbi-section' }, [
			E('h3', {}, 'Installation Info'),
			E('div', { 'style': 'padding:8px 16px' }, [
				makeInfoRow('Version', version),
				makeInfoRow('Architecture', arch),
				makeInfoRow('Download Source', downloadSource),
				makeInfoRow('Storage Mode', storageMode),
				makeInfoRow('Binary Directory', binDir)
			])
		]);
	},

	renderSubnetRouting: function() {
		return E('div', { 'class': 'cbi-section' }, [
			E('h3', {}, 'Subnet Routing'),
			E('div', { 'style': 'padding:8px 16px' }, [
				E('p', { 'style': 'margin:0 0 8px;color:#666' },
					'Create the OpenWrt network interface and firewall zone for Tailscale subnet routing.'),
				E('button', {
					'class': 'cbi-button cbi-button-action',
					'click': ui.createHandlerFn(this, 'handleSetupFirewall')
				}, 'Configure Network Interface and Firewall')
			])
		]);
	},

	render: function(data) {
		var installInfo = data[1] || {};
		var m, s, o;

		m = new form.Map('tailscale', 'Tailscale Configuration',
			'Configure the Tailscale service. Changes take effect after Save & Apply.');

		s = m.section(form.NamedSection, 'settings', 'tailscale', 'General Settings');
		s.anonymous = false;
		s.addremove = false;

		o = s.option(form.Value, 'port', 'Port', 'UDP port for WireGuard traffic.');
		o.datatype = 'port';
		o.default = '41641';
		o.rmempty = false;

		o = s.option(form.ListValue, 'net_mode', 'Networking Mode', 'Choose between TUN mode and userspace networking mode.');
		o.value('auto', 'Auto (prefer TUN mode, fallback to userspace networking mode)');
		o.value('tun', 'TUN mode');
		o.value('userspace', 'Userspace networking mode');
		o.default = 'auto';

		o = s.option(form.ListValue, 'proxy_listen', 'Proxy Listen',
			'Proxy listen scope for SOCKS5/HTTP proxy in userspace networking mode.');
		o.value('localhost', 'Localhost only');
		o.value('lan', 'LAN (0.0.0.0)');
		o.default = 'localhost';
		o.depends('net_mode', 'userspace');

		o = s.option(form.Flag, 'log_stdout', 'Log Standard Output', 'Enable standard output logging for tailscaled.');
		o.default = '1';
		o.rmempty = false;

		o = s.option(form.Flag, 'log_stderr', 'Log Standard Error', 'Enable standard error logging for tailscaled.');
		o.default = '1';
		o.rmempty = false;

		return m.render().then(L.bind(function(node) {
			node.appendChild(this.renderInstallationInfo(installInfo));
			node.appendChild(this.renderSubnetRouting());
			return node;
		}, this));
	},

	handleSetupFirewall: function() {
		ui.showModal('Configuring Subnet Routing', [
			E('p', { 'class': 'spinning' }, 'Creating network interface and firewall zone...')
		]);

		return callSetupFirewall().then(function(result) {
			ui.hideModal();
			if (result && result.code === 0)
				ui.addNotification(null,
					E('p', {}, 'Network interface and firewall zone configured successfully.'), 'info');
			else
				ui.addNotification(null,
					E('p', {}, 'Configuration failed: ' + ((result && result.stdout) || 'Unknown error')),
					'danger');
		}).catch(function(err) {
			ui.hideModal();
			ui.addNotification(null, E('p', {}, 'RPC error: ' + err.message), 'danger');
		});
	}
});
