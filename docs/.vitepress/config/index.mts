import { defineConfig } from 'vitepress'
import { en } from './en.mts'
import { zh } from './zh.mts'

export default defineConfig({
  base: '/openwrt-tailscale/',
  title: 'OpenWrt Tailscale',
  description: 'Auto-updating Tailscale installation manager for OpenWrt routers',

  lastUpdated: true,
  cleanUrls: true,

  head: [
    ['link', { rel: 'icon', type: 'image/svg+xml', href: '/openwrt-tailscale/logo.svg' }],
  ],

  locales: {
    en: { label: 'English', ...en },
    zh: { label: '简体中文', ...zh },
  },

  themeConfig: {
    socialLinks: [
      { icon: 'github', link: 'https://github.com/fl0w1nd/openwrt-tailscale' },
    ],
    search: {
      provider: 'local',
    },
  },
})
