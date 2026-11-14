// Library persistence: one JSON file in app-private document storage
// (spec/ui.md, "Library data"). Large URLs make a key-value store a poor fit.
import { File, Paths } from 'expo-file-system';
import { emptyLibrary, parseLibrary, serializeLibrary, type Library } from '../core/library';

const FILE_NAME = 'library.json';

function libraryFile(): File {
  return new File(Paths.document, FILE_NAME);
}

/** Reads the library, or an empty one when the file is missing or unreadable. */
export function loadLibrary(): Library {
  try {
    const file = libraryFile();
    return file.exists ? parseLibrary(file.textSync()) : emptyLibrary;
  } catch (e) {
    console.warn('binfire: could not read library', e);
    return emptyLibrary;
  }
}

/** Writes the library (via a temporary file, then a move, so a crash never leaves half a file). */
export async function storeLibrary(lib: Library): Promise<void> {
  const tmp = new File(Paths.document, FILE_NAME + '.tmp');
  try {
    await tmp.write(serializeLibrary(lib));
    tmp.moveSync(libraryFile(), { overwrite: true });
  } catch {
    // Some platforms refuse to move over an existing file; fall back to a direct write.
    try {
      await libraryFile().write(serializeLibrary(lib));
    } catch (e) {
      console.warn('binfire: could not write library', e);
    }
  }
}
