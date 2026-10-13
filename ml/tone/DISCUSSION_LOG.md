## A4 Discussion Log: Findings from trying an off-the-shelf tone model

## Goal: 
Test an existing audEERING emotion recoginition model with 10-20 test_audio clips.
Determine if arousal, valence, and dominance values can correctly be mapped to the project's tone tags - excited, upset, calm, or none - based on the project's existing thresholds. 
This will serve as the baseline for the audio section of the project.

## Initial Model Loading and Evaluation
test_audeering.py was created as an initial test script to verify that the audEERING model could be loaded successfully and produce arousal, dominance, and valence scores

This standard transforemrs pipeline produced model-weight mismatch warnings so results were not used. Further investigation showed that the checkpoint uses the Wav2Vec2ForSpeechClassification architecture which the installed Transformers version did not expose in the class directly. As a result, the model architecture was recreated using Wav2Vec2Model which allowed the checkpoint to load without missing/unexpected weight warnings and produced plausible emotion scores. This corrected implementation was incorporated into the final baseline.py

I have deleted the test_audeering.py file even because its sole purpose was as a development and sanity-check tool so it was not needed in the final A4 implementation.

## Model:
The chosen audEERING model from Hugging Face: audeering/wav2vec2-large-robust-12-ft-emotion-msp-dim

The processor and the model are loaded in with local_files_only = True and so you must download the model files before running baseline.py. The model weights are not included in this repo.

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

Note that these 28 MP3 recordings (comprised of three differnt voices) were stored locally in ml/tone/test_audio and are excluded from Git through the repo's .gitignore. If you are reproducing the experiment, you will need to provide your own MP3 recordings inside the aforementioned folder. The recordings used for this baseline test were organized with filenames beginning with 'calm', 'excited', 'neutral', and 'upset'

## Tag mapping
The following are the project's threshold specified in docs/GRAPTION_CONTEXT.md:

-Arousal > 0.65 && valence > 0.55 --> excited
-Arousal > 0.65 && valence < 0.40 --> upset
-Arousal < 0.30 --> calm
-Otherwise --> none

However, the thresholds were modified upon testing with several different individual's audio
-Arousal > 0.64 && valence > 0.45 --> excited
-Arousal > 0.47 && valence < 0.40 --> upset
-0.38 < Arousal < 0.48 && valence > 0.45 --> calm
-Otherwise --> none

The new thresholds were maintained during this initial experiment bc goal was pure evaluation of an existing model with an existing baseline

## Initial Model Results
The model successfully processed all 28 test clips.

The model correctly produced 'excited' for 2 of the 3 excited clips and returned 'none' for the third excited clip even though human review identified clear positive energy and high-pitched tone.

All three clips intended to represent 'upset' were classified as 'none'. Human review found clear frustration, annoyance, or negativity in all three.

The calm clips were frequently classified as 'none'. Human review identified that two out of the three as clearly calm, while the third could be interpreted as either none or calm because there is slight excitement.

One none clip was classified as 'calm' even though human review identified it as neutral and monotone. The two other neutral clips were classified as 'none' which aligned with human review.

## Threshold-Tuned Model Results
After reviewing the initial model results, I adjusted the arousal and valence thresholds to be able to better distinguish calm, excited, upset, and no tones

The model correctly classified 5/8 clips as 'calm' which was a significant improvement from the initial model results. Human review identified that the three that were incorrectly classified as 'none' could be interpreted as either none or calm because there is slight excitement.

The model correctly produced 'excited' for 6 of the 8 excited clips. However, it returned 'calm' and 'upset' for the two incorrectly labeled clips even though human review identified clear positive energy and high-pitched tone.

One none clip was classified as 'calm' even though human review identified it as neutral and monotone. The three other neutral clips were classified as 'none' which aligned with human review.

The modified thresholds made a major improvement in correctly classifying the 'upset clips' - 6/8. The other 2 clips intended to represent 'upset' were classified as 'none'. Human review found clear frustration, annoyance, or negativity in all upset clips.


## Notes from Initial Human Review (before threshold changes + collection of additional audio clips)

Human review was used to determine whether the model's tags matched the perceived tone of each recording based on the predefined thresholds (no tuning yet). Filename categories were treated as intended categories.

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
The initial results showed that the fixed threshold mapping does not consistently match the perceived vocal tone.

Clearest example was with 'upset': all three clips sounded upset to human review, but none reached the required arousal threshold of 0.65.

The model also confused low arousal with calmness once because the arousal score of 'neutral_clip_one' was below 0.30 and thus received a 'calm' tag even though human review identified that the voice was monotone and neutral as opposed to calm.

The model also missed calm clips because their arousal scores were above the 0.30 calm threshold.

Results suggest that arousal alone cannot accurately distinguish calm from neutral and that the current threhold combination might be too restrictive for different representations of upset/excited voices.

However, threshold tuning produced better results. In the latest 28-clip run, 20 clips were correctly classified, with 6/8 ecited clips and 6/8 upset clips correctly labeled. However, 3/8 calm clips were still misclassifeid and 1 clip intended to receive a 'none' tag was labeled as 'calm'. Thus, we can conclude that adjusting arousal and valence thresholds can improve the mapping between emotion scores and the tone tags.

## Timings
Initial Test Timings: Individual inference times were recorded (and displayed) and ranged from 0.22 to 0.57 seconds per clip, with an average of approximately 0.36 secs

New (most recent) Test Timings: Individual inference times were recorded (and displayed) and ranged from 0.30 to 0.72 seconds per clip.

## Takeaway
The audEERING model works as an off-the-shelf baseline and can produce useful emotion dimensions without training a custom model. Initial testing showed that fixed thresholds do not consistentily agree with human review across the test clips of varying emotions, thus prompting further experimentation with the tag mapping.

The tuned thresholds had pretty good preliminary results; however, with any test, more clips could improve accuracy. 
As a result, the baseline should be treated as an initial comparison as opposed to the final tone classifier. Additional test and threshold tuning may be needed before using these tags within the larger project.