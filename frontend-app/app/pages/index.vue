<script setup lang="ts">
import { Button } from '~/components/ui/button'
</script>

<template>
  <main class="flex min-h-screen items-center justify-center px-6 py-16">
    <section class="w-full max-w-2xl space-y-8 text-center">
      <div class="space-y-3">
        <p class="text-sm font-semibold uppercase tracking-[0.2em] text-slate-500">
          Frontend App
        </p>
        <h1 class="text-4xl font-bold tracking-tight text-slate-950 sm:text-6xl">
          Nuxt is ready.
        </h1>
        <p class="mx-auto max-w-xl text-lg leading-8 text-slate-600">
          A small starting point for the application, with Tailwind CSS and a
          shadcn-vue-compatible UI foundation.
        </p>
      </div>
      <div class="flex justify-center gap-3">
        <Button>Get started</Button>
        <Button variant="outline">Learn more</Button>
      </div>
    </section>
  </main>
</template>
