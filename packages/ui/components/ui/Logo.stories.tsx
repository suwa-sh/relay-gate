import type { Meta, StoryObj } from '@storybook/nextjs-vite'
import { Logo } from './Logo'

const meta: Meta<typeof Logo> = {
  title: 'Brand/Logo',
  component: Logo,
  tags: ['autodocs'],
}
export default meta
type Story = StoryObj<typeof Logo>

export const Variants: Story = {
  render: () => (
    <div style={{ display: 'flex', gap: 32, alignItems: 'center', flexWrap: 'wrap' }}>
      <div style={{ textAlign: 'center' }}>
        <Logo variant="full" height={40} />
        <div style={{ fontSize: 12, color: 'var(--foreground-secondary)', marginTop: 8 }}>full</div>
      </div>
      <div style={{ textAlign: 'center' }}>
        <Logo variant="icon" height={40} />
        <div style={{ fontSize: 12, color: 'var(--foreground-secondary)', marginTop: 8 }}>icon</div>
      </div>
      <div style={{ textAlign: 'center' }}>
        <Logo variant="stacked" height={60} />
        <div style={{ fontSize: 12, color: 'var(--foreground-secondary)', marginTop: 8 }}>stacked</div>
      </div>
    </div>
  ),
}
