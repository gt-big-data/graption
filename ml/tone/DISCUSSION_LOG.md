# A4 Discussion Log: Findings from trying an off-the-shelf tone model

## Goal: 
Test an existing audEERING emotion recoginition model with 10-20 test_audio clips.
Determine if arousal, valence, and dominance values can correctly be mapped to the project's tone tags - excited, upset, calm, or none - based on the project's existing thresholds. 
This will serve as the baseline for the audio section of the project.

## Initial Model Loading and Evaluation
test_audeering.py was created as an initial test script to verify that the audEERING model could be loaded successfully and produce arousal, dominance, and valence scores

This standard transforemrs pipeline produced model-weight mismatch warnings so results were not used. Further investigation showed that the checkpoint uses the Wav2Vec2ForSpeechClassification architecture which the installed Transformers version did not expose in the class directly. As a result, the model architecture was recreated using Wav2Vec2Model which allowed the checkpoint to load without missing/unexpected weight warnings and produced plausible emotion scores. This corrected implementation was incorporated into the final baseline.py

I have delted the test_audeering.py file even because its sole purpose was as a development and sanity-check tool so it was not needed in the final A4 implementation.

## Model:
The chosen audEERING model: audeering/wav2vec2-large-robust-12-ft-emotion-msp-dim

Outputs: 
-arousal: energy level behind the speech
-valence: how positive or negative the emotion in the speech sounds
-dominance: degree of control / authority the speaker projects

Use the arousal and valence scores  of each audio clip to assign a tone tag

## Test Data + Audio Preprocessing
Recorded test audio clips were 48 kHz in .mp3 format. However the audEERING model expected 16 kHz audio.

Thus, baseline.py does the following:
-Converts all the test_audio clips from stereo to mono
-Resamples audio from 48kHz to 16kHz
-Does not save modified audio files to the disk

Note that these 12 MP3 recordings were stored locally in ml/tone/test_audio and are excluded from Git through the repo's .gitignore. If you are reproducing the experiment, you will need to provide your own MP3 recordings inside the aforementioned folder. The recordings used for this baseline test were organized with filenames beginning with 'calm', 'excited', 'neutral', and 'upset'

## Tag mapping
The following are the project's threshold specified in docs/GRAPTION_CONTEXT.md:

-Arousal > 0.65 && valence > 0.55 --> excited
-Arousal > 0.65 && valence < 0.40 --> upset
-Arousal < 0.30 --> calm
-Otherwise --> none

Thresholds were maintained during this initial experiment bc goal was pure evaluation of an existing model with an existing baseline

## Initial Model Results
The model successfully processed all 12 test clips.

The model correctly produced 'excited' for 2 of the 3 excited clips and returned 'none' for the third excited clip even though human review identified clear positive energy and high-pitched tone.

All three clips intended to represent 'upset' were classified as 'none'. Human review found clear frustration, annoyance, or negativity in all three.

The calm clips were frequently classified as 'none'. Human review identified that two out of the three as clearly calm, while the third could be interpreted as either neutral or calm because there is slight excitement.

One neutral clip was classified as 'calm' even though human review identified it as neutral and monotone. The two other neutral clips were classified as 'none' which aligned with human review.

# Notes from Human Review

Human review was used to determine whether the model's tags matched the perceived tone of each recording. Filename categories were treated as intended categories.

1. calm_clip_one
    - Model Tag: none
    - Human Review: incorrect
    - Notes: Clearly calm
2. calm_clip_two
    - Model Tag: none
    - Human Review: Incorrect
    - Notes: Clearly calm
3. calm_clip_three
    - Model Tag: none
    - Human Review: Reasonable
    - Notes: Between calm and neutral; possible undertones of slightly excited
4. excited_clip_one
    - Model Tag: excited
    - Human Review: correct
    - Notes: Very excited
5. excited_clip_two:
    - Model Tag: excited
    - Human Review: correct
    - Notes: High energy and strong intonation
6. excited_clip_three:
    - Model Tag: none
    - Human Review: incorrect
    - Notes: There was high pitch and clear positive energy
7. neutral_clip_one:
    - Model Tag: calm
    - Human Review: incorrect
    - Notes: Very monotone; lacks the airy quality of a calm voice
8. neutral_clip_two:
    - Model Tag: none
    - Human Review: correct
    - Notes: Neutral with no clear emotional tone
9. neutral_clip_three:
    - Model Tag: none
    - Human Review: correct
    - Notes: Neutral with no clear emotional tone
10. upset_clip_one:
    - Model Tag: none
    - Human Review: incorrect
    - Notes: clear fustration and negativity
11. upset_clip_two:
    - Model Tag: none
    - Human review: incorrect
    - Notes: clear signs of frustration via big sigh and annoyance
12. upset_clip_three:
    - Model Tag: none
    - Human review: incorrect
    - Notes: rushed, high pitched, angry

## Findings
The fixed threshold mapping does not consistently match the perceived vocal tone.

Clearest example was with 'upset': all three clips sounded upset to human review, but none reached the required arousal threshold of 0.65.

The model also confused low arousal with calmness once because the arousal score of 'neutral_clip_one' was below 0.30 and thus received a 'calm' tag even though human review identified that the voice was monotone and neutral as opposed to calm.

The model also missed calm clips because their arousal scores were above the 0.30 calm threshold.

Results suggest that arousal alone cannot accurately distinguish calm from neutral and that the current threhold combination might be too restrictive for different representations of upset/excited voices

## Timings
Individual inference times were recorded (and displayed) and ranged from 0.22 to 0.57 seconds per clip, with an average of approximately 0.36 secs

## Takeaway
The audEERING model works as an off-the-shelf baseline and can produce useful emotion dimensions without training a custom model. However, the current fixed tag thresholds do not consistentily agree with human review across the test clips of varying emotions.

As a result, the baseline should be treated as an initial comparison as opposed to the final tone classifier. Additional test and threshold tuning may be needed before using these tags within the larger project.


