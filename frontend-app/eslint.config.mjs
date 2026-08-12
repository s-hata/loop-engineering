import eslint from '@eslint/js'
import tsParser from '@typescript-eslint/parser'
import prettier from 'eslint-config-prettier'
import simpleImportSort from 'eslint-plugin-simple-import-sort'
import vue from 'eslint-plugin-vue'
import vueParser from 'vue-eslint-parser'

export default [
  {
    ignores: [
      '.nuxt/**',
      '.output/**',
      'coverage/**',
      'node_modules/**',
      'playwright-report/**',
      'test-results/**',
    ],
  },
  eslint.configs.recommended,
  ...vue.configs['flat/recommended'],
  {
    files: ['**/*.{js,mjs,cjs,ts,tsx,vue}'],
    languageOptions: {
      globals: {
        defineNuxtConfig: 'readonly',
        process: 'readonly',
        URL: 'readonly',
      },
      parser: vueParser,
      parserOptions: {
        parser: tsParser,
        sourceType: 'module',
        ecmaVersion: 'latest',
      },
    },
    plugins: {
      'simple-import-sort': simpleImportSort,
    },
    rules: {
      'no-console': 'warn',
      'simple-import-sort/imports': 'error',
      'simple-import-sort/exports': 'error',
      'vue/multi-word-component-names': 'off',
      'vue/no-v-html': 'off',
    },
  },
  prettier,
]
