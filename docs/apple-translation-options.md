# Apple Translation Options and Jev

AirTranslate 1.16.0 adds two separate optional controls. Apple translation options use the system translation service. Jev sends text to an external service only when enabled.

## Apple Translation

In **Settings > General > Apple translation**, choose **Realtime** (the default) or **Quality first**. Quality first requests Apple's higher-fidelity strategy where available and may take longer. System support and language-pair availability determine which model Apple uses; selecting it does not confirm Apple Intelligence model use or better translation.

These controls require macOS 26.4 or later and apply only to workflows using Apple text translation. Earlier supported systems continue using the existing realtime translation path. When a quality-first request fails, AirTranslate retries with realtime translation and uses that strategy for the same language pair until the app restarts.

Under **Keep these terms unchanged**, enter one product name or technical term per line. The list supports up to 100 unique terms, 80 characters per term, and 8,000 characters overall. Overlong terms are excluded. Terms are stored locally in app preferences. This is spelling preservation during translation, not speech-recognition correction.

If Apple changes a registered term, AirTranslate keeps the affected segment in its original language rather than displaying or speaking that invalid translation. Remove the term from the list if full translation is more useful for that segment.

## Experimental Jev Candidate Selection

1. In **Settings > API Keys > TypeSafe · Jev**, save your own TypeSafe API key.
2. Select Apple transcription with translation output.
3. In **Settings > General**, enable **Jev candidate selection (experimental)** after reading the data-transfer notice.

The option starts off. Jev selects only from recognition candidates already supplied by Apple. It does not generate a rewritten transcript. Candidates, source and target languages, and up to six recent transcript segments are sent directly to TypeSafe over HTTPS. Context is limited to 1,000 UTF-8 bytes, each candidate to 4,000 UTF-8 bytes, with up to three alternatives alongside the original. Audio is not sent to Jev.

AirTranslate uses a separate device-local Keychain entry. Requests use an ephemeral HTTP session without persistent cookies or a disk response cache, and redirects are rejected. Provider account access, data handling, retention, quotas, and charges remain subject to TypeSafe's terms. AirTranslate does not bundle a key or operate a relay.

Each request can add up to 1.2 seconds of response waiting, in addition to any existing translation queue wait and processing time. Already queued segments may share a request, up to four per batch, without waiting to fill a batch. Missing alternatives, low confidence, abstention, invalid responses, service errors, and timeouts keep the original transcript. Stop capture before changing this setting.

This remains experimental. A configured key does not confirm service access. Broad recognition accuracy, billing, quotas, retention, and general end-to-end latency have not been verified, and accuracy improvement is not guaranteed.

## Floating-only Workflow

Choose the floating mode control, then **Floating only** to start an idle session or resume a paused session. AirTranslate minimizes the main window only after capture starts. If startup fails, the main controls remain available. The menu bar and app menus provide capture controls while the overlay itself remains text-only.

Choosing the combined main-and-floating view does not itself start a new capture. The previous-caption block can show up to two lines for eight seconds while the current caption advances. Reduce Motion is respected.
