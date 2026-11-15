import type { CommonFilters } from '@hentai-park/source-contract';

type Values = Record<string, unknown>;
const invalid = () => Object.assign(new Error('BAD_REQUEST'), { code: 'BAD_REQUEST', statusCode: 400, publicError: true, causeCategory: 'validation', retryable: false });

export function normalizeFilters(input: Values | undefined, declaration: CommonFilters | undefined): { filters: Values; common?: Values } {
  const filters = { ...input };
  const common = filters.common;
  delete filters.common;
  if (common === undefined) return { filters };
  if (!common || typeof common !== 'object' || Array.isArray(common) || Object.keys(common).length > 5) throw invalid();
  let sorted = 0;
  for (const [dimension, raw] of Object.entries(common)) {
    const supported = declaration && Object.hasOwn(declaration, dimension) ? declaration[dimension as keyof CommonFilters] : undefined;
    if (!supported || !raw || typeof raw !== 'object' || Array.isArray(raw)) throw invalid();
    const value = raw as Values;
    if (Object.keys(value).some(key => !['min', 'max', 'order'].includes(key))) throw invalid();
    const ranges = supported.range === true ? ['min', 'max'] : supported.range ?? [];
    for (const bound of ['min', 'max'] as const) {
      const number = value[bound];
      if (number !== undefined && (!ranges.includes(bound) || typeof number !== 'number' || !Number.isFinite(number) || (dimension !== 'score' && number < 0) || (dimension !== 'duration' && !Number.isInteger(number)))) throw invalid();
    }
    if (typeof value.min === 'number' && typeof value.max === 'number' && value.min > value.max) throw invalid();
    if (value.order !== undefined) {
      const orders = supported.sort === true ? ['asc', 'desc'] : supported.sort ?? [];
      if (!orders.includes(value.order as 'asc' | 'desc') || ++sorted > 1) throw invalid();
    }
  }
  return { filters, common: common as Values };
}
