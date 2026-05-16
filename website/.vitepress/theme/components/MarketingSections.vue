<script setup>
import { computed, nextTick, onBeforeUnmount, ref, watch } from "vue";

const screenshotVersion = "20260422c";
const githubUrl = "https://github.com/undercoveragents/undercoveragents";
const availabilityLabel = "Coming soon";

const mainFeatures = [
  {
    key: "dashboard",
    title: "Dashboard",
    icon: "fa-solid fa-gauge-high",
    image: `/images/dashboard.png?v=${screenshotVersion}`,
    alt: "Admin dashboard screenshot",
    description:
      "Start from an operator dashboard with the fastest path into agents, tools, missions, runs, and the rest of the admin surface.",
  },
  {
    key: "agents",
    title: "Agents",
    icon: "fa-solid fa-user-secret",
    image: `/images/agents.png?v=${screenshotVersion}`,
    alt: "Agents show page screenshot",
    description:
      "Configure reusable AI operators with instructions, model settings, tools, skills, subagents, and capabilities. Agents power playground chats, internal automation, and published channels.",
  },
  {
    key: "tools",
    title: "Tools",
    icon: "fa-solid fa-wrench",
    image: `/images/tools.png?v=${screenshotVersion}`,
    alt: "Tools show page screenshot",
    description:
      "Turn SQL, MCP, retrieval, and mission flows into callable runtime capabilities. Tools keep data access and external actions explicit, assignable, and reviewable from the admin surface.",
  },
  {
    key: "missions",
    title: "Missions",
    icon: "fa-solid fa-diagram-project",
    image: `/images/missions.png?v=${screenshotVersion}`,
    alt: "Missions show page screenshot",
    description:
      "Design multi-step workflows with visual nodes, control flow, HTTP calls, tools, state, and outputs. Missions turn isolated prompting into repeatable orchestration with runtime visibility.",
  },
];

const platformFeatures = [
  {
    title: "Agents",
    icon: "fa-solid fa-user-secret",
    description: "Reusable runtime units with instructions, tools, skills, subagents, and capability plugins.",
  },
  {
    title: "Tools",
    icon: "fa-solid fa-wrench",
    description: "Callable capabilities backed by queries, retrieval, integrations, and mission execution.",
  },
  {
    title: "Skills",
    icon: "fa-solid fa-book-open",
    description: "Progressive knowledge libraries that agents can discover and activate at runtime.",
  },
  {
    title: "Missions",
    icon: "fa-solid fa-diagram-project",
    description: "Visual orchestration for control flow, tool usage, state, and structured outputs.",
  },
  {
    title: "Channels",
    icon: "fa-solid fa-tower-broadcast",
    description: "Publish agents or missions through branded chat, API, and messaging entry points with scoped targets.",
  },
  {
    title: "RAG",
    icon: "fa-solid fa-arrow-right-to-bracket",
    description: "Retrieval pipelines for ingest, chunking, embedding, and grounded search over your content.",
  },
  {
    title: "Playground",
    icon: "fa-solid fa-flask",
    description: "A fast operator surface for trying agents, inspecting responses, and watching live tool usage.",
  },
  {
    title: "Agent Alpha",
    icon: "fa-solid fa-robot",
    description: "A built-in admin assistant that can inspect resources and delegate to designer subagents inside the app.",
  },
  {
    title: "Inspector",
    icon: "fa-solid fa-microscope",
    description: "Runtime trace views for browsing chats, messages, tool calls, and execution history after the fact.",
  },
  {
    title: "Mission Control",
    icon: "fa-solid fa-satellite-dish",
    description: "Execution visibility for mission runs, including status, history, and runtime progression.",
  },
  {
    title: "Test Suites",
    icon: "fa-solid fa-vial-circle-check",
    description: "Repeatable evaluation flows for validating agent and mission behavior before rollout.",
  },
  {
    title: "Connectors",
    icon: "fa-solid fa-plug",
    description: "Trusted connections to providers, databases, authentication systems, and external services.",
  },
  {
    title: "Operations",
    icon: "fa-solid fa-briefcase",
    description: "Tenant-local workspaces for grouping agents, tools, missions, channels, and RAG flows by intent.",
  },
  {
    title: "Plugins",
    icon: "fa-solid fa-puzzle-piece",
    description: "Extensible architecture for loading tool, connector, capability, and RAG modules into the app.",
  },
  {
    title: "Tenants",
    icon: "fa-solid fa-building",
    description: "Top-level isolation for customer spaces, core resources, tenant-specific administration, and local logins.",
  },
];

const activeShotKey = ref(null);
const galleryCloseButton = ref(null);
let lastFocusedElement = null;

const activeShot = computed(() => mainFeatures.find((feature) => feature.key === activeShotKey.value) || null);

function openGallery(feature) {
  activeShotKey.value = feature.key;
}

function closeGallery() {
  activeShotKey.value = null;
}

function showGalleryShot(direction) {
  const currentIndex = mainFeatures.findIndex((feature) => feature.key === activeShotKey.value);
  const nextIndex = (currentIndex + direction + mainFeatures.length) % mainFeatures.length;

  activeShotKey.value = mainFeatures[nextIndex].key;
}

function handleGalleryKeydown(event) {
  if (!activeShot.value) return;

  if (event.key === "Escape") {
    closeGallery();
  } else if (event.key === "ArrowLeft") {
    showGalleryShot(-1);
  } else if (event.key === "ArrowRight") {
    showGalleryShot(1);
  }
}

function clearGallerySideEffects() {
  if (typeof window === "undefined") return;

  window.removeEventListener("keydown", handleGalleryKeydown);
  document.documentElement.classList.remove("ua-gallery-open");
}

watch(activeShot, async (shot, previousShot) => {
  if (typeof window === "undefined") return;

  if (shot && !previousShot) {
    lastFocusedElement = document.activeElement;
    document.documentElement.classList.add("ua-gallery-open");
    window.addEventListener("keydown", handleGalleryKeydown);
    await nextTick();
    galleryCloseButton.value?.focus();
  } else if (!shot) {
    clearGallerySideEffects();
    lastFocusedElement?.focus?.();
    lastFocusedElement = null;
  }
});

onBeforeUnmount(clearGallerySideEffects);
</script>

<template>
  <div id="overview" class="ua-home">
    <section id="main-features" class="ua-product">
      <div class="ua-section-heading">
        <p class="ua-kicker">Main features</p>
        <h2>Dashboard, agents, tools, and missions</h2>
        <p>The operator entry point plus the core surfaces teams use to build, inspect, and operate AI systems.</p>
      </div>

      <div class="ua-product-grid">
        <article
          v-for="feature in mainFeatures"
          :key="feature.title"
          :class="['ua-product-card', `ua-product-card--${feature.title.toLowerCase()}`]"
        >
          <button class="ua-product-shot" type="button" :aria-label="`Open ${feature.title} screenshot gallery`" @click="openGallery(feature)">
            <img :class="['ua-product-image', `ua-product-image--${feature.key}`]" :src="feature.image" :alt="feature.alt" />
            <span class="ua-product-zoom" aria-hidden="true">
              <i class="fa-solid fa-up-right-and-down-left-from-center"></i>
            </span>
          </button>
          <div class="ua-product-copy">
            <div class="ua-feature-heading ua-feature-heading--main">
              <span class="ua-icon-pill ua-icon-pill--main" aria-hidden="true">
                <i :class="feature.icon"></i>
              </span>
              <h3>{{ feature.title }}</h3>
            </div>
            <p>{{ feature.description }}</p>
          </div>
        </article>
      </div>
    </section>

    <section id="features" class="ua-secondary">
      <div class="ua-section-heading">
        <p class="ua-kicker">Full platform</p>
        <h2>Features</h2>
        <p>The surrounding platform that turns those core surfaces into something teams can ship, inspect, and operate.</p>
      </div>

      <ul class="ua-feature-list">
        <li v-for="feature in platformFeatures" :key="feature.title" class="ua-feature-list-item">
          <span class="ua-icon-pill ua-icon-pill--list" aria-hidden="true">
            <i :class="feature.icon"></i>
          </span>
          <div class="ua-feature-list-copy">
            <h3>{{ feature.title }}</h3>
            <p>{{ feature.description }}</p>
          </div>
        </li>
      </ul>
    </section>

    <section class="ua-cta ua-cta--compact">
      <div>
        <p class="ua-kicker">Get started</p>
        <h2>Self-host it, adapt it, or start in the cloud</h2>
        <p>Undercover Agents is open source, Rails-native, and designed for teams that need one place to build and operate AI systems.</p>
      </div>

      <div class="ua-cta-actions">
        <button class="ua-link-button ua-link-button--brand ua-link-button--disabled" type="button" disabled>
          <span>Try in Cloud</span>
          <span class="ua-status-badge">{{ availabilityLabel }}</span>
        </button>
        <button class="ua-link-button ua-link-button--muted ua-link-button--disabled" type="button" disabled :data-target-url="githubUrl">
          <span>Download on GitHub</span>
        </button>
      </div>
    </section>

    <Teleport to="body">
      <div
        v-if="activeShot"
        class="ua-shot-gallery"
        role="dialog"
        aria-modal="true"
        :aria-label="`${activeShot.title} screenshot gallery`"
        @click.self="closeGallery"
      >
        <div class="ua-shot-gallery__chrome">
          <p>{{ activeShot.title }}</p>
          <button ref="galleryCloseButton" class="ua-shot-gallery__close" type="button" aria-label="Close gallery" @click="closeGallery">
            <i class="fa-solid fa-xmark" aria-hidden="true"></i>
          </button>
        </div>

        <button class="ua-shot-gallery__nav ua-shot-gallery__nav--previous" type="button" aria-label="Previous screenshot" @click="showGalleryShot(-1)">
          <i class="fa-solid fa-chevron-left" aria-hidden="true"></i>
        </button>

        <figure class="ua-shot-gallery__figure">
          <img class="ua-shot-gallery__image" :src="activeShot.image" :alt="activeShot.alt" />
        </figure>

        <button class="ua-shot-gallery__nav ua-shot-gallery__nav--next" type="button" aria-label="Next screenshot" @click="showGalleryShot(1)">
          <i class="fa-solid fa-chevron-right" aria-hidden="true"></i>
        </button>
      </div>
    </Teleport>
  </div>
</template>
