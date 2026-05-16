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

    <button class="ua-link-button ua-link-button--muted ua-link-button--disabled" type="button" disabled :data-target-url="githubUrl">
      <span>Download on GitHub</span>
    </button>
  </div>
</template>
