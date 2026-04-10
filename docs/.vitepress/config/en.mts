import type { DefaultTheme, LocaleSpecificConfig } from 'vitepress'

export const en: LocaleSpecificConfig<DefaultTheme.Config> = {
  lang: 'en-US',
  description: 'Auto-updating Tailscale installation manager for OpenWrt routers',

  themeConfig: {
    nav: [
      { text: 'Guide', link: '/en/guide/installation' },
      { text: 'Changelog', link: '/en/changelog' },
    ],

    sidebar: {
      '/en/guide/': [
        {
          text: 'Getting Started',
          items: [
            { text: 'Installation', link: '/en/guide/installation' },
            { text: 'Download Sources', link: '/en/guide/download-sources' },
            { text: 'Storage Modes', link: '/en/guide/storage-modes' },
          ],
        },
        {
          text: 'Networking',
          items: [
            { text: 'Networking Mode', link: '/en/guide/net-mode' },
            { text: 'Subnet Routing', link: '/en/guide/subnet-routing' },
            { text: 'Userspace Mode', link: '/en/guide/userspace-mode' },
          ],
        },
        {
          text: 'Management',
          items: [
            { text: 'CLI Commands', link: '/en/guide/commands' },
            { text: 'Configuration', link: '/en/guide/configuration' },
            { text: 'Auto-Update', link: '/en/guide/auto-update' },
            { text: 'LuCI Interface', link: '/en/guide/luci' },
          ],
        },
        {
          text: 'More',
          items: [
            { text: 'Troubleshooting', link: '/en/guide/troubleshooting' },
            { text: 'Uninstall', link: '/en/guide/uninstall' },
          ],
        },
      ],
      '/en/changelog': [
        { text: 'Changelog', link: '/en/changelog' },
      ],
    },

    editLink: {
      pattern: 'https://github.com/fl0w1nd/openwrt-tailscale/edit/main/docs/:path',
      text: 'Edit this page on GitHub',
    },
  },
}
