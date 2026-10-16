type MemberOrderKey = {
  readonly name: string;
  readonly path: string;
  readonly line: number;
  readonly anchor: string;
};

export function compareMembers(a: MemberOrderKey, b: MemberOrderKey, order?: 'definition' | 'name'): number;
export function enhanceMembers(root?: Document | Element): void;
