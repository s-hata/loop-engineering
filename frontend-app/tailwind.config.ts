import type { Config } from 'tailwindcss'

export default {
  content: ['./app/**/*.{vue,js,ts}', './components/**/*.{vue,js,ts}'],
  theme: {
    extend: {
      colors: {
        border: 'hsl(var(--border))',
        foreground: 'hsl(var(--foreground))',
        primary: {
          DEFAULT: 'hsl(var(--primary))',
          foreground: 'hsl(var(--primary-foreground))',
        },
      },
      borderRadius: {
        lg: 'var(--radius)',
      },
    },
  },
  plugins: [],
} satisfies Config
