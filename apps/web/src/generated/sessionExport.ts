/**
 * Graption meeting export and sync contract. Writers emit v2 (sound events, tone detail,
 * titles and deletion markers); v1 imports remain supported. Text and metadata only, never
 * audio or video. Times are seconds since session start on the phone monotonic clock.
 */
export interface SessionExport {
    app_version?:   string;
    export_version: ExportVersion;
    /**
     * Date and time the export was created.
     */
    exported_at: string;
    sessions:    SessionElement[];
}

export enum ExportVersion {
    The1 = "1",
    The2 = "2",
}

export interface SessionElement {
    captions: CaptionElement[];
    /**
     * Redacted deletion marker for offline sync. Deleted meetings are hidden.
     */
    deleted_at?: string;
    /**
     * Session duration in seconds.
     */
    duration:      number;
    id:            string;
    sound_events?: SoundEventElement[];
    /**
     * Date and time the session started. The exporter must convert P8's saved startedAt Date to
     * an RFC 3339 date-time string with a timezone.
     */
    started_at: string;
    title?:     string;
}

export interface CaptionElement {
    caption_id:     string;
    model_versions: ModelVersions;
    /**
     * Tracked face ID selected by timestamped speaker fusion; unknown when ambiguous or off
     * camera. Display a stable color and numbered speaker label.
     */
    speaker_id:   string;
    t_end:        number;
    t_start:      number;
    text:         string;
    tone_probs?:  ToneProbs;
    tone_scores?: ToneScores;
    /**
     * Saved tone label, or null when no tone is available.
     */
    tone_tag: null | string;
}

export interface ModelVersions {
    asd?:  string;
    asr:   string;
    tone?: string;
}

export interface ToneProbs {
    anger?:   number;
    disgust?: number;
    fear?:    number;
    happy?:   number;
    neutral?: number;
    sad?:     number;
}

export interface ToneScores {
    arousal?:   number;
    dominance?: number;
    valence?:   number;
}

export interface SoundEventElement {
    confidence:    number;
    id:            string;
    label:         string;
    model_version: string;
    t:             number;
}
