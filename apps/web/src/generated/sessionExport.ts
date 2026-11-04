export interface SessionExport {
    app_version?:   string;
    export_version: ExportVersion;
    exported_at:    string;
    sessions:       Session[];
}

export enum ExportVersion {
    The1 = "1",
}

export interface Session {
    captions:   Caption[];
    duration:   number;
    id:         string;
    started_at: string;
}

export interface Caption {
    caption_id:     string;
    model_versions: ModelVersions;
    speaker_id:     string;
    t_end:          number;
    t_start:        number;
    text:           string;
    tone_tag:       null | string;
}

export interface ModelVersions {
    asd?:  string;
    asr:   string;
    tone?: string;
}
