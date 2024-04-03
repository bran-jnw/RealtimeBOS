using System;
using System.Collections;
using System.Collections.Generic;
using System.ComponentModel.Design;
using UnityEngine;
using UnityEngine.Video;

public enum CalculationMode { PixelDelta, MacroBlockSearch}
public enum FrameReference { StaticFrame = 0, PreviousFrame, TemporalSmoothing}

public enum CaptureSource{ WebCam = 0, Video }


public class RealtimeBOS : MonoBehaviour
{
    [SerializeField] CaptureSource captureSource = CaptureSource.WebCam;
    [SerializeField] string cameraName;
    [SerializeField] Material BOS_Material;
    [SerializeField] Material MacroBlockSearch_Material;
    [SerializeField] CalculationMode calculationMode;
    [SerializeField] float newInputFrameWeight = 0.1f;
    [SerializeField] FrameReference frameReference = FrameReference.StaticFrame;
    [SerializeField] bool saveReferenceNow = false;
    [SerializeField] bool useGreyScale = false;
    [SerializeField] bool deNoise = false;
    [SerializeField] bool averageOutput = true;
    [SerializeField] float newOutputFrameWeight = 0.05f;
    [SerializeField] bool processBOS = true;
    [SerializeField] bool _saveToDisk = false;


    WebCamTexture m_camTexture;
    RenderTexture m_referenceTexture;
    VideoPlayer m_videoPlayer;


    // Start is called before the first frame update
    void Start()
    {
        m_videoPlayer = GetComponent<VideoPlayer>();

        if(captureSource == CaptureSource.WebCam)
        {
            WebCamDevice[] webCams = WebCamTexture.devices;
            if (webCams.Length > 1)
            {
                for (int i = 0; i < webCams.Length; i++)
                {
                    if (webCams[i].name.Contains(cameraName))
                    {
                        m_camTexture = new WebCamTexture(webCams[i].name);
                        print("Using camera " + webCams[i].name);
                        m_camTexture.Play();
                    }
                }
            }
        }
         
    }

    // Update is called once per frame
    void Update()
    {
        if(Input.GetKeyDown(KeyCode.Space))
        {
            saveReferenceNow = true;
        }

        if(Input.GetKeyDown(KeyCode.P) && m_videoPlayer != null &&  captureSource == CaptureSource.Video)
        {
            if(m_videoPlayer.isPlaying)
            {
                m_videoPlayer.Pause();
            }
            else
            {
                m_videoPlayer.Play();
            }
        }
    }

    void SetTextureReference(RenderTexture source)
    {
        if(m_referenceTexture == null)
        {
            m_referenceTexture = new RenderTexture(source);
            Graphics.CopyTexture(source, m_referenceTexture);
            BOS_Material.SetTexture("_ReferenceTex", m_referenceTexture);
            MacroBlockSearch_Material.SetTexture("_PreviousFrame", m_referenceTexture);
        }        

        if (frameReference == FrameReference.StaticFrame || frameReference == FrameReference.PreviousFrame)
        {            
            Graphics.CopyTexture(source, m_referenceTexture);
            BOS_Material.SetTexture("_ReferenceTex", m_referenceTexture);
            MacroBlockSearch_Material.SetTexture("_PreviousFrame", m_referenceTexture);
        }
        else if(frameReference == FrameReference.TemporalSmoothing)
        {
            RenderTexture tempReference = RenderTexture.GetTemporary(source.descriptor);
            BOS_Material.SetTexture("_ReferenceTex", m_referenceTexture);
            BOS_Material.SetFloat("_newWeight", newInputFrameWeight);
            MacroBlockSearch_Material.SetTexture("_PreviousFrame", m_referenceTexture);
            Graphics.Blit(source, tempReference, BOS_Material, 2);
            Graphics.CopyTexture(tempReference, m_referenceTexture);
            RenderTexture.ReleaseTemporary(tempReference);
        }
    }

    RenderTexture bufferedInputFrame;
    RenderTexture bufferedOutputFrame;

    long videoFrameCount = 0;
    void OnRenderImage(RenderTexture source, RenderTexture destination)
    {
        if(captureSource == CaptureSource.WebCam && m_camTexture == null)
        {
            SetTextureReference(source);
            return;
        }

        if (captureSource == CaptureSource.Video && m_videoPlayer == null)
        {
            SetTextureReference(source);
            return;
        }

        if (processBOS)
        {
            bool updateFrame = false;
            if(captureSource == CaptureSource.WebCam)
            {
                updateFrame = m_camTexture.didUpdateThisFrame;
            }
            else
            {
                if(m_videoPlayer.frame != videoFrameCount)
                {
                    videoFrameCount = m_videoPlayer.frame;
                    updateFrame = true;
                }
            }

            if (updateFrame)
            {
                Texture captureTexture;
                if(captureSource == CaptureSource.WebCam)
                {
                    captureTexture = m_camTexture;
                }
                else
                {
                    captureTexture = m_videoPlayer.texture;
                }

                if(captureTexture == null)
                {
                    return;
                }

                RenderTexture frameInput = RenderTexture.GetTemporary(captureTexture.width, captureTexture.height);
                RenderTexture worker = RenderTexture.GetTemporary(captureTexture.width, captureTexture.height);
                RenderTexture singleFrameResult = RenderTexture.GetTemporary(captureTexture.width, captureTexture.height);
                RenderTexture data = RenderTexture.GetTemporary(captureTexture.width / 8, captureTexture.height / 8);
                data.filterMode = FilterMode.Point;                

                if (useGreyScale)
                {
                    Graphics.Blit(captureTexture, frameInput, BOS_Material, 0);
                }
                else
                {
                    Graphics.Blit(captureTexture, frameInput);
                }

                if (deNoise)
                {
                    Graphics.Blit(frameInput, destination, BOS_Material, 3);
                    Graphics.Blit(destination, frameInput);
                }

                if (m_referenceTexture != null)
                {
                    if(calculationMode == CalculationMode.PixelDelta)
                    {
                        //first get difference
                        Graphics.Blit(frameInput, worker, BOS_Material, 1);
                        //then check window                        
                        Graphics.Blit(worker, singleFrameResult, BOS_Material, 4);
                    }
                    else if(calculationMode == CalculationMode.MacroBlockSearch)
                    {
                        Graphics.Blit(frameInput, data, MacroBlockSearch_Material, 0);
                        MacroBlockSearch_Material.SetTexture("_Data", data);
                        Graphics.Blit(frameInput, singleFrameResult, MacroBlockSearch_Material, 1);                        
                    }

                    if (bufferedInputFrame == null)
                    {
                        bufferedInputFrame = new RenderTexture(frameInput);
                    }
                    Graphics.Blit(frameInput, bufferedInputFrame);

                    if (bufferedOutputFrame == null)
                    {
                        bufferedOutputFrame = new RenderTexture(frameInput);
                    }

                    if (averageOutput && bufferedOutputFrame != null)
                    {
                        BOS_Material.SetTexture("_ReferenceTex", bufferedOutputFrame);
                        BOS_Material.SetFloat("_newWeight", newOutputFrameWeight);
                        Graphics.Blit(singleFrameResult, worker, BOS_Material, 2);
                        Graphics.Blit(worker, bufferedOutputFrame);
                        Graphics.Blit(worker, destination);
                    }
                    else
                    {
                        Graphics.CopyTexture(singleFrameResult, bufferedOutputFrame);
                        Graphics.Blit(singleFrameResult, destination);
                    }

                    if(_saveToDisk)
                    {
                        SaveTextureToFileUtility.SaveRenderTextureToFile(singleFrameResult, System.IO.Path.Combine(System.IO.Directory.GetParent(Application.dataPath).FullName, "_output", videoFrameCount.ToString()), SaveTextureToFileUtility.SaveTextureFileFormat.PNG);
                    }
                }
                else
                {
                    Graphics.Blit(frameInput, destination);
                }

                if (saveReferenceNow || frameReference == FrameReference.PreviousFrame || frameReference == FrameReference.TemporalSmoothing)
                {
                    saveReferenceNow = false;
                    SetTextureReference(frameInput);
                }

                //fixes warning about desitnation not being last Blit
                Graphics.SetRenderTarget(destination);

                RenderTexture.ReleaseTemporary(frameInput);
                RenderTexture.ReleaseTemporary(worker);
                RenderTexture.ReleaseTemporary(singleFrameResult);
                RenderTexture.ReleaseTemporary(data);
            }
            //display the last real frame captured from camera
            else if (bufferedInputFrame != null)
            {
                Graphics.SetRenderTarget(bufferedInputFrame);
                //Graphics.Blit(bufferedFrame, destination);
            }
            
        }        
        //do nothing
        else
        {
            Graphics.Blit(m_camTexture, destination);
        }
    }
}
