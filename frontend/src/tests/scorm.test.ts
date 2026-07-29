import { describe, expect, it } from 'vitest'
import { isScormCompletionSignal } from '@/utils/scorm'

describe('isScormCompletionSignal', () => {
	it('accepts SCORM 1.2 passed and completed lesson statuses', () => {
		expect(isScormCompletionSignal('cmi.core.lesson_status', 'passed')).toBe(
			true,
		)
		expect(isScormCompletionSignal('cmi.core.lesson_status', 'completed')).toBe(
			true,
		)
	})

	it('accepts SCORM 2004 completion and success statuses', () => {
		expect(isScormCompletionSignal('cmi.completion_status', 'completed')).toBe(
			true,
		)
		expect(isScormCompletionSignal('cmi.success_status', 'passed')).toBe(true)
	})

	it('normalizes status casing and surrounding whitespace', () => {
		expect(
			isScormCompletionSignal('cmi.core.lesson_status', ' Completed '),
		).toBe(true)
	})

	it('does not complete failed or incomplete attempts', () => {
		expect(isScormCompletionSignal('cmi.core.lesson_status', 'failed')).toBe(
			false,
		)
		expect(
			isScormCompletionSignal('cmi.core.lesson_status', 'incomplete'),
		).toBe(false)
		expect(isScormCompletionSignal('cmi.completion_status', 'incomplete')).toBe(
			false,
		)
	})
})
