---
layout: false
---

<script setup>
if (typeof window !== 'undefined') {
  const lang = navigator.language || ''
  const target = lang.startsWith('zh') ? '/zh/' : '/en/'
  window.location.replace(target)
}
</script>

<meta http-equiv="refresh" content="0; url=/en/">
