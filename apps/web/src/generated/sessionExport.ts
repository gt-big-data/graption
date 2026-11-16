/**
 * Graption saved-session export contract v1. Created only when the user taps Export.
 * Contains saved captions and session metadata; no audio or raw events. Duration and
 * caption times are in seconds; caption times are relative to session start.
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
}

export interface SessionElement {
    captions: CaptionElement[];
    /**
     * Session duration in seconds.
     */
    duration: number;
    id:       string;
    /**
     * Date and time the session started. The exporter must convert P8's saved startedAt Date to
     * an RFC 3339 date-time string with a timezone.
     */
    started_at: string;
}

export interface CaptionElement {
    caption_id:     string;
    model_versions: ModelVersions;
    /**
     * Face id chosen by fusion, or "unknown" (off-screen/ambiguous; shown as "Someone").
     */
    speaker_id: string;
    t_end:      number;
    t_start:    number;
    text:       string;
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
