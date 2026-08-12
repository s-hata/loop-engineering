<script setup lang="ts">
import { cva, type VariantProps } from 'class-variance-authority'

import { cn } from '~/utils/cn'

const buttonVariants = cva(
  'inline-flex items-center justify-center whitespace-nowrap rounded-lg text-sm font-medium transition-colors focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-slate-400 disabled:pointer-events-none disabled:opacity-50',
  {
    variants: {
      variant: {
        default: 'bg-slate-950 px-4 py-2 text-white hover:bg-slate-800',
        outline:
          'border border-slate-200 bg-white px-4 py-2 text-slate-950 hover:bg-slate-50',
      },
      size: {
        default: 'h-10',
        sm: 'h-9 px-3',
      },
    },
    defaultVariants: {
      variant: 'default',
      size: 'default',
    },
  },
)

type ButtonVariants = VariantProps<typeof buttonVariants>

interface Props {
  class?: string
  size?: ButtonVariants['size']
  variant?: ButtonVariants['variant']
}

const props = withDefaults(defineProps<Props>(), {
  size: 'default',
  variant: 'default',
})
</script>

<template>
  <button
    :class="
      cn(buttonVariants({ size: props.size, variant: props.variant }), props.class)
    "
    type="button"
  >
    <slot />
  </button>
</template>
