---
layout: false
---

<script setup>
if (typeof window !== 'undefined') {
  const base = import.meta.env.BASE_URL || '/'
  const lang = navigator.language || ''
  const target = new URL(lang.startsWith('zh') ? 'zh/' : 'en/', window.location.origin + base).pathname
  window.location.replace(target)
}
</script>

Documentation is loading...
