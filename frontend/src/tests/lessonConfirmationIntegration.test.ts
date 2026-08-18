import { readFileSync } from 'node:fs'
import { fileURLToPath, URL } from 'node:url'
import { describe, expect, it } from 'vitest'

const source = (relativePath: string) =>
	readFileSync(fileURLToPath(new URL(relativePath, import.meta.url)), 'utf8')

describe('Confirm and Continue integration', () => {
	it('keeps the completion mode editable in the lesson form', () => {
		const form = source('../pages/LessonForm.vue')
		expect(form).toContain('v-model="lesson.completion_mode"')
		expect(form).toContain("'Confirm and Continue'")
	})

	it('requires confirmation, submits it, and blocks automatic completion', () => {
		const lesson = source('../pages/Lesson.vue')
		expect(lesson).toContain('const confirmationRequired = computed(')
		expect(lesson).toContain('{ confirmed: true }')
		expect(lesson).toContain('if (isStudentView.value) {')
		expect(lesson).toContain("switchLesson('next', true)")
		expect(lesson).toContain('confirmed: params.confirmed ? 1 : 0')
		expect(lesson).toContain(
			'if (isConfirmAndContinueMode(lesson.data?.completion_mode)) return'
		)
		expect(lesson).toContain("{{ __('Confirm and Continue') }}")
	})

	it('keeps video lessons automatic and the completion selector read-only', () => {
		const form = source('../pages/LessonForm.vue')
		expect(form).toContain(':disabled="lessonHasVideo"')
		expect(form).toContain("lesson.completion_mode = 'Automatic'")
	})
})
