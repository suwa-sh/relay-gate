import type { Preview } from '@storybook/nextjs-vite'
import '../src/app/globals.css'

const preview: Preview = {
  parameters: {
    controls: {
      matchers: {
        color: /(background|color)$/i,
        date: /Date$/i,
      },
    },
    a11y: {
      // 'todo' - show a11y violations in the test UI only
      // 'error' - fail CI on a11y violations
      // 'off' - skip a11y checks entirely
      test: 'todo',
    },
  },
  globalTypes: {
    portal: {
      description: 'ポータル切替',
      defaultValue: 'ops',
      toolbar: {
        title: 'Portal',
        icon: 'user',
        items: [{ value: 'ops', title: '運用ポータル (ops)' }],
        dynamicTitle: true,
      },
    },
    theme: {
      description: 'テーマ切替',
      defaultValue: 'light',
      toolbar: {
        title: 'Theme',
        icon: 'circlehollow',
        items: [
          { value: 'light', title: 'Light' },
          { value: 'dark', title: 'Dark' },
        ],
        dynamicTitle: true,
      },
    },
  },
  decorators: [
    (Story, context) => {
      const portal = context.globals.portal || 'ops'
      const theme = context.globals.theme || 'light'

      document.documentElement.setAttribute('data-portal', portal)
      document.documentElement.classList.toggle('dark', theme === 'dark')
      document.documentElement.classList.toggle('light', theme === 'light')

      document.body.style.background = 'var(--background)'
      document.body.style.color = 'var(--foreground)'

      return Story()
    },
  ],
}

export default preview
