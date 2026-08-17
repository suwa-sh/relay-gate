import type { Meta, StoryObj } from '@storybook/nextjs-vite'
import { Button } from './Button'

const meta: Meta<typeof Button> = {
  title: 'UI/Button',
  component: Button,
  tags: ['autodocs'],
}
export default meta
type Story = StoryObj<typeof Button>

export const Primary: Story = { args: { variant: 'primary', children: '実行する' } }
export const Secondary: Story = { args: { variant: 'secondary', children: 'キャンセル' } }
export const Destructive: Story = { args: { variant: 'destructive', children: '中止する' } }
export const Small: Story = { args: { variant: 'primary', size: 'sm', children: 'y (実行)' } }
