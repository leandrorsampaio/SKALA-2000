// PK-4 Console reference bundle (window.PK4). Documentation only: the product is native; these shapes name what each instrument needs.
type LampColor = 'red' | 'amber' | 'green' | 'white';
type LampState = 'off' | 'on' | 'flash' | 'test';
declare namespace PK4 {
  function Panel(o: { title: string; width?: number; finish?: 'hammer' | 'ivory' | 'graphite' }, children?: HTMLElement[]): HTMLElement;
  function LampWindow(o: { label: string; color?: LampColor; state?: LampState; code?: boolean; ink?: 'light' | 'dark' }): HTMLElement;
  function screw(size?: number): SVGElement;
  function finish(name: 'hammer' | 'ivory' | 'graphite'): void;
  function LampLens(o: { label: string; color?: LampColor; state?: LampState }): HTMLElement;
  function lamp(el: HTMLElement, state: LampState): void;
  function NixieReadout(o: { label: string; value: string; unit?: string; xl?: boolean; labelWidth?: number }): HTMLElement;
  function nixie(row: HTMLElement, value: string): void; // same length as the readout
  function DrumCounter(o: { label: string; digits: number; value?: number; unit?: string }): HTMLElement;
  function drum(col: HTMLElement, value: number): void; // forward only
  function MovingCoilMeter(o: { label: string; value?: number; red?: [number, number]; unit?: string }): HTMLElement;
  function meter(el: HTMLElement, fraction: number): void;
  function EdgewiseMeter(o: { label: string; value?: number }): HTMLElement;
  function edge(el: HTMLElement, fraction: number): void;
  function PushButton(o: { cap: string; label: string; tone?: 'amber' | 'red'; momentary?: boolean; confirmAfter?: number; simulate?: 'fail'; onConfirm?: (lit: boolean) => void }): HTMLElement;
  function RoundPushButton(o: { cap: string; label: string; on?: boolean; confirmAfter?: number }): HTMLElement;
  function GuardedButton(o: { cap: string; label: string; key?: boolean; onConfirm?: () => void }): HTMLElement;
  function RotarySelector(o: { positions?: number; value?: number; label?: string; size?: number; onChange?: (position: number) => void }): HTMLElement;
  function ToggleSwitch(o: { label: string; on?: boolean; onChange?: (on: boolean) => void }): HTMLElement;
  function PencilStrip(o: { value?: string; label?: string }): HTMLInputElement;
  function Annunciator(o: { sessions?: number; pencil?: string[]; code?: boolean; rows: { id: string; label: string; cap: string; color: LampColor; alarm?: boolean }[] }): { el: HTMLElement; grille: HTMLElement; set(rowId: string, session: number, active: boolean): void; acknowledge(): void; silence(): void; lampTest(on: boolean): void };
  const sound: { enabled: boolean; click(): void; clunk(): void; tick(): void; buzzer(on: boolean): void };
}
