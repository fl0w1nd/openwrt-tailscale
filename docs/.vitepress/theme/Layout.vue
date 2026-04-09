<script setup lang="ts">
import DefaultTheme from 'vitepress/theme'
import { useRouter, useData } from 'vitepress'
import { onMounted } from 'vue'

const { Layout } = DefaultTheme
const router = useRouter()
const { localeIndex } = useData()

onMounted(() => {
  // Redirect root path based on browser language
  if (router.route.path === '/' || router.route.path === '') {
    const lang = navigator.language || ''
    const target = lang.startsWith('zh') ? '/zh/' : '/en/'
    router.go(target)
  }
})
</script>

<template>
  <Layout />
</template>
