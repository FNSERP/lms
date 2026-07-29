const normalized = (value: unknown): string =>
	String(value ?? '')
		.trim()
		.toLowerCase()

export function isScormCompletionSignal(key: string, value: unknown): boolean {
	const status = normalized(value)
	if (key === 'cmi.core.lesson_status') {
		return status === 'passed' || status === 'completed'
	}
	if (key === 'cmi.completion_status') return status === 'completed'
	if (key === 'cmi.success_status') return status === 'passed'
	return false
}
