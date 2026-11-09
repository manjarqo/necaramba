// Application: activate the next input source.
import {nextSourceIndex} from '../domain/layoutShortcut.js';

/** inputSources: { sources(): array, currentIndex(): number, activate(index) } */
export function switchToNextLayout(inputSources) {
    const next = nextSourceIndex(inputSources.currentIndex(), inputSources.sources().length);
    if (next !== null)
        inputSources.activate(next);
}
