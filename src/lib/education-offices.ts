/** NEIS 시도교육청 코드. 브라우저에서도 안전하게 import할 수 있는 순수 상수 모듈입니다. */
export const EDUCATION_OFFICES = [
  { code: "B10", name: "서울특별시교육청", shortName: "서울" },
  { code: "C10", name: "부산광역시교육청", shortName: "부산" },
  { code: "D10", name: "대구광역시교육청", shortName: "대구" },
  { code: "E10", name: "인천광역시교육청", shortName: "인천" },
  { code: "F10", name: "전남광주통합특별시교육청(광주)", shortName: "광주" },
  { code: "G10", name: "대전광역시교육청", shortName: "대전" },
  { code: "H10", name: "울산광역시교육청", shortName: "울산" },
  { code: "I10", name: "세종특별자치시교육청", shortName: "세종" },
  { code: "J10", name: "경기도교육청", shortName: "경기" },
  { code: "K10", name: "강원특별자치도교육청", shortName: "강원" },
  { code: "M10", name: "충청북도교육청", shortName: "충북" },
  { code: "N10", name: "충청남도교육청", shortName: "충남" },
  { code: "P10", name: "전북특별자치도교육청", shortName: "전북" },
  { code: "Q10", name: "전남광주통합특별시교육청(전남)", shortName: "전남" },
  { code: "R10", name: "경상북도교육청", shortName: "경북" },
  { code: "S10", name: "경상남도교육청", shortName: "경남" },
  { code: "T10", name: "제주특별자치도교육청", shortName: "제주" },
] as const;

export type EducationOfficeCode = (typeof EDUCATION_OFFICES)[number]["code"];

export const EDUCATION_OFFICE_CODES = EDUCATION_OFFICES.map((office) => office.code) as [
  EducationOfficeCode,
  ...EducationOfficeCode[],
];

const EDUCATION_OFFICE_CODE_SET: ReadonlySet<string> = new Set(EDUCATION_OFFICE_CODES);

export function isEducationOfficeCode(value: string): value is EducationOfficeCode {
  return EDUCATION_OFFICE_CODE_SET.has(value);
}
