<script setup>
const githubUrl = "https://github.com/undercoveragents/undercoveragents";
const availabilityLabel = "Coming soon";
</script>

<template>
  <div class="ua-hero-actions" aria-label="Product availability">
    <button class="ua-link-button ua-link-button--brand ua-link-button--disabled" type="button" disabled>
      <span>Try in Cloud</span>
      <span class="ua-status-badge">{{ availabilityLabel }}</span>
    </button>

    <a class="ua-link-button ua-link-button--muted" :href="githubUrl" target="_blank" rel="noreferrer noopener">
      <span>Download on GitHub</span>
    </a>
  </div>
</template>
