﻿Param
	(
		[Parameter(Position=0)][xml]$XmlAnalysis,
		[Parameter(Position=1)]$XmlAnalysisInstanceIndex,
		[Parameter(Position=2)]$csvFile,
		[Parameter(Position=3)][array]$CounterList,
		[Parameter(Position=4)][xml]$xmlCounterLogCounterInstanceList,
		[Parameter(Position=5)]$rHtml,
		[Parameter(Position=6)]$rQuestions,
		[Parameter(Position=7)]$interval="AUTO"
	)

Set-StrictMode -Version 2

[Void] [Reflection.Assembly]::LoadFile("C:\Program Files (x86)\Microsoft Chart Controls\Assemblies\System.Windows.Forms.DataVisualization.dll")


$global:sDateTimePattern = (get-culture).datetimeformat.ShortDatePattern + " " + (get-culture).datetimeformat.LongTimePattern
$global:NumberOfValuesPerTimeSlice = -1

#// Chart Constants
$CHART_LINE_THICKNESS = 3 #// 2 is thin, 3 is normal, 4 is thick
$CHART_WIDTH = 1024        #// Width in pixels
$CHART_HEIGHT = 480       #// height in pixels
$CHART_MAX_INSTANCES = 10 #// the maximum number of counter instance in a chart
$global:CHART_MAX_NUMBER_OF_AXIS_X_INTERVALS = 30 #// The maximum allowed X axis labels in the chart.

$global:aCounterLogCounterList = $CounterList
$global:XmlCounterLogCounterInstanceList = $xmlCounterLogCounterInstanceList
$global:aTime = ""
$global:alCounterData = $null #// 2 dimensional array
$global:alQuantizedIndex = $null
$global:alCounterData = $null #// 2 dimensional array
$global:IsAnalysisIntervalCalculated = $False
$global:alQuantizedIndex = $null
$global:alQuantizedTime = $null
$global:htCounterInstanceStats = @{}	
$global:sPerfLogFilePath = $csvFile
$global:sPerfLogTimeZone = ""
$global:htQuestionVariables = $rQuestions
$global:alCounterExpressionProcessedHistory = New-Object System.Collections.ArrayList

$global:htScript = @{"Version" = "v2.3.2";"ScriptFileObject" = "";"Culture"="";"LocalizedDecimal" = "";"LocalizedThousandsSeparator" = "";"BeginTime" = "";"EndTime" = "";"ScriptFileLastModified" = "";"SessionGuid"= "";"MainHeader"="";"UserTempDirectory"="";"DebugLog"="";"SessionDateTimeStamp"="";"SessionWorkingDirectory" = ""}
$global:htHtmlReport = $rHtml

#// For Alerts
[boolean] $global:IsMinEvaulated = $False
[boolean] $global:IsAvgEvaulated = $False
[boolean] $global:IsMaxEvaulated = $False
[boolean] $global:IsTrendEvaulated = $False

$xmlAnalysisInstance = $XmlAnalysis.PAL.ANALYSIS[$XmlAnalysisInstanceIndex]

$global:BeginTime = $null
$global:EndTime = $null

Function Get-LocalizedThousandsSeparator()
{
	Return (get-culture).numberformat.NumberGroupSeparator
}

Function IsGreaterThanZero
{
    param($Value)
    If (IsNumeric $Value)
    {
        If ($Value -gt 0)
        {
            Return $True
        }
        Else
        {
            Return $False
        }
    }
    Else
    {
        Return $False
    }
}

Function GetQuantizedTimeSliceTimeRange
{
    param($TimeSliceIndex)
    $u = $alQuantizedTime.Count - 1
    If ($TimeSliceIndex -ge $u)
    {
    	$LastTimeSlice = $alQuantizedTime[$u]
    	$EndTime = $alQuantizedTime[$u].AddSeconds($AnalysisInterval)
        $Date1 = Get-Date $([datetime]$alQuantizedTime[$u]) -format $global:sDateTimePattern
        $Date2 = Get-Date $([datetime]$EndTime) -format $global:sDateTimePattern
        [string] $ResultTimeRange = "$Date1" + ' - ' + "$Date2"
    }
    Else
    {
        $Date1 = Get-Date $([datetime]$alQuantizedTime[$TimeSliceIndex]) -format $global:sDateTimePattern
        $Date2 = Get-Date $([datetime]$alQuantizedTime[$TimeSliceIndex+1]) -format $global:sDateTimePattern
        [string] $ResultTimeRange = "$Date1" + ' - ' + "$Date2"
    }
    $ResultTimeRange
}


Function CreateAlert
{
    param($TimeSliceIndex,$CounterInstanceObject,$IsMinThresholdBroken=$False,$IsAvgThresholdBroken=$False,$IsMaxThresholdBroken=$False,$IsTrendThresholdBroken=$False,$IsMinEvaluated=$False,$IsAvgEvaluated=$False,$IsMaxEvaluated=$False,$IsTrendEvaluated=$False)
    #// The following are provided via global variables to make it simple for users to use.
    
    [string] $sCounterInstanceName = $CounterInstanceObject.CounterPath
    If ($($sCounterInstanceName.Contains('INTERNAL_OVERALL_COUNTER_STATS')) -eq $True)
    {
        $IsInternalOnly = $True
    }
    Else
    {
        $IsInternalOnly = $False
    }
    
    $IsSameCounterAlertFound = $False
    :XmlAlertLoop ForEach ($XmlAlert in $CurrentXmlAnalysisInstance.SelectNodes('./ALERT'))
    {
        If (($XmlAlert.TIMESLICEINDEX -eq $TimeSliceIndex) -and ($XmlAlert.COUNTER -eq $CounterInstanceObject.CounterPath))
        {
            #// Update alert
            If ($([int] $ThresholdPriority) -ge $([int] $XmlAlert.CONDITIONPRIORITY))
            {
                $XmlAlert.CONDITIONCOLOR = $ThresholdColor
                $XmlAlert.CONDITION = $ThresholdCondition
                $XmlAlert.CONDITIONNAME = $ThresholdName
                $XmlAlert.CONDITIONPRIORITY = $ThresholdPriority
            }

            If ($IsMinThresholdBroken -eq $True)
            {
                If ($([int] $ThresholdPriority) -ge $([int] $XmlAlert.MINPRIORITY))
                {
                    $XmlAlert.MINCOLOR = $ThresholdColor
                    $XmlAlert.MINPRIORITY = $ThresholdPriority
                }
            }
            
            If ($IsAvgThresholdBroken -eq $True)
            {
                If ($([int] $ThresholdPriority) -ge $([int] $XmlAlert.AVGPRIORITY))
                {
                    $XmlAlert.AVGCOLOR = $ThresholdColor
                    $XmlAlert.AVGPRIORITY = $ThresholdPriority
                }
            }
            
            If ($IsMaxThresholdBroken -eq $True)
            {
                If ($([int] $ThresholdPriority) -ge $([int] $XmlAlert.MAXPRIORITY))
                {
                    $XmlAlert.MAXCOLOR = $ThresholdColor
                    $XmlAlert.MAXPRIORITY = $ThresholdPriority
                }
            }
            
            If ($IsTrendThresholdBroken -eq $True)
            {
                If ($([int] $ThresholdPriority) -ge $([int] $XmlAlert.TRENDPRIORITY))
                {
                    $XmlAlert.TRENDCOLOR = $ThresholdColor
                    $XmlAlert.TRENDPRIORITY = $ThresholdPriority
                }
            }
            $IsSameCounterAlertFound = $True
            Break XmlAlertLoop
        }
    }
    
    If ($IsSameCounterAlertFound -eq $False)
    {        
        #// Add the alert
        $XmlNewAlert = $XmlAnalysis.CreateElement("ALERT")
        $XmlNewAlert.SetAttribute("TIMESLICEINDEX", $TimeSliceIndex)
        $XmlNewAlert.SetAttribute("TIMESLICERANGE", $(GetQuantizedTimeSliceTimeRange -TimeSliceIndex $TimeSliceIndex))
        $XmlNewAlert.SetAttribute("CONDITIONCOLOR", $ThresholdColor)
        $XmlNewAlert.SetAttribute("CONDITION", $ThresholdCondition)
        $XmlNewAlert.SetAttribute("CONDITIONNAME", $ThresholdName)
        $XmlNewAlert.SetAttribute("CONDITIONPRIORITY", $ThresholdPriority)
        $XmlNewAlert.SetAttribute("COUNTER", $CounterInstanceObject.CounterPath)
        $XmlNewAlert.SetAttribute("PARENTANALYSIS", $($CurrentXmlAnalysisInstance.NAME))
        $XmlNewAlert.SetAttribute("ISINTERNALONLY", $IsInternalOnly)
        
        If ($IsMinThresholdBroken -eq $True)
        {
            $XmlNewAlert.SetAttribute("MINCOLOR", $ThresholdColor)
            $XmlNewAlert.SetAttribute("MINPRIORITY", $ThresholdPriority)
        }
        Else
        {
            If ($IsMinEvaulated -eq $True)
            {
                #// 00FF00 is a light green
                $XmlNewAlert.SetAttribute("MINCOLOR", 'White')
                $XmlNewAlert.SetAttribute("MINPRIORITY", '0')
            }
            Else
            {
                $XmlNewAlert.SetAttribute("MINCOLOR", 'White')
                $XmlNewAlert.SetAttribute("MINPRIORITY", '0')
            }
        }
        
        If ($IsAvgThresholdBroken -eq $True)
        {
            $XmlNewAlert.SetAttribute("AVGCOLOR", $ThresholdColor)
            $XmlNewAlert.SetAttribute("AVGPRIORITY", $ThresholdPriority)
        }
        Else
        {
            If ($IsAvgEvaulated -eq $True)
            {
                #// 00FF00 is a light green
                $XmlNewAlert.SetAttribute("AVGCOLOR", 'White')
                $XmlNewAlert.SetAttribute("AVGPRIORITY", '0')
            }
            Else
            {
                $XmlNewAlert.SetAttribute("AVGCOLOR", 'White')
                $XmlNewAlert.SetAttribute("AVGPRIORITY", '0')
            }
        }
        
        If ($IsMaxThresholdBroken -eq $True)
        {
            $XmlNewAlert.SetAttribute("MAXCOLOR", $ThresholdColor)
            $XmlNewAlert.SetAttribute("MAXPRIORITY", $ThresholdPriority)
        }
        Else
        {
            If ($IsMaxEvaulated -eq $True)
            {
                #// 00FF00 is a light green
                $XmlNewAlert.SetAttribute("MAXCOLOR", 'White')
                $XmlNewAlert.SetAttribute("MAXPRIORITY", '0')
            }
            Else
            {
                $XmlNewAlert.SetAttribute("MAXCOLOR", 'White')
                $XmlNewAlert.SetAttribute("MAXPRIORITY", '0')
            }
        }
        
        If ($IsTrendThresholdBroken -eq $True)
        {
            $XmlNewAlert.SetAttribute("TRENDCOLOR", $ThresholdColor)
            $XmlNewAlert.SetAttribute("TRENDPRIORITY", $ThresholdPriority)
        }
        Else
        {
            If ($IsTrendEvaulated -eq $True)
            {
                #// 00FF00 is a light green
                $XmlNewAlert.SetAttribute("TRENDCOLOR", 'White')
                $XmlNewAlert.SetAttribute("TRENDPRIORITY", '0')
            }
            Else
            {
                $XmlNewAlert.SetAttribute("TRENDCOLOR", 'White')
                $XmlNewAlert.SetAttribute("TRENDPRIORITY", '0')
            }
        }
        $XmlNewAlert.SetAttribute("MIN", $($CounterInstanceObject.QuantizedMin[$TimeSliceIndex]))
        $XmlNewAlert.SetAttribute("AVG", $($CounterInstanceObject.QuantizedAvg[$TimeSliceIndex]))
        $XmlNewAlert.SetAttribute("MAX", $($CounterInstanceObject.QuantizedMax[$TimeSliceIndex]))
        $XmlNewAlert.SetAttribute("TREND", $($CounterInstanceObject.QuantizedTrend[$TimeSliceIndex]))
        [void] $CurrentXmlAnalysisInstance.AppendChild($XmlNewAlert)
    }
}




Function StaticChartThreshold
{
    param($CollectionOfCounterInstances,$MinThreshold,$MaxThreshold,$UseMaxValue=$True,$IsOperatorGreaterThan=$True)
    
    If ($IsOperatorGreaterThan -eq $True)
    {
        ForEach ($CounterInstanceOfCollection in $CollectionOfCounterInstances)
        {
            If (($CounterInstanceOfCollection.Max -gt $MaxThreshold) -and ($UseMaxValue -eq $True))
            {
                $MaxThreshold = $CounterInstanceOfCollection.Max
            }
        }
    }
    Else
    {
        ForEach ($CounterInstanceOfCollection in $CollectionOfCounterInstances)
        {
            If (($CounterInstanceOfCollection.Min -lt $MinThreshold) -and ($UseMaxValue -eq $True))
            {
                $MinThreshold = $CounterInstanceOfCollection.Min
            }
        }    
    }
    
    :ChartCodeLoop ForEach ($CounterInstanceOfCollection in $CollectionOfCounterInstances)
    {
        ForEach ($iValue in $CounterInstanceOfCollection.Value)
        {
            [void] $MinSeriesCollection.Add($MinThreshold)
            [void] $MaxSeriesCollection.Add($MaxThreshold)
        }
        Break ChartCodeLoop
    }
}


Function StaticThreshold
{
    param($CollectionOfCounterInstances,$Operator,$Threshold,$IsTrendOnly=$False)
    
    For ($i=0;$i -lt $CollectionOfCounterInstances.Count;$i++)
    {
        $oCounterInstance = $CollectionOfCounterInstances[$i]
        
        For ($t=0;$t -lt $alQuantizedTime.Count;$t++)
        {
            $IsMinThresholdBroken = $False
            $IsAvgThresholdBroken = $False
            $IsMaxThresholdBroken = $False
            $IsTrendThresholdBroken = $False
            $IsMinEvaulated = $False
            $IsAvgEvaulated = $False
            $IsMaxEvaulated = $False
            $IsTrendEvaulated = $False
            
            If ($IsTrendOnly -eq $False)
            {
                #/////////////////////////
                #// IsMinThresholdBroken
                #/////////////////////////
                If (($oCounterInstance.QuantizedMin[$t] -ne '-') -and ($oCounterInstance.QuantizedMin[$t] -ne $null))
                {
    				switch ($Operator)
                    {
                        'gt'
                        {
                            If ($oCounterInstance.QuantizedMin[$t] -gt $Threshold)
                            {
                                $IsMinThresholdBroken = $True
                            }
                    	}
                        'ge'
                        {
                            If ($oCounterInstance.QuantizedMin[$t] -ge $Threshold)
                            {
                                $IsMinThresholdBroken = $True
                            }
                    	}
                    	'lt'
                        {
                            If ($oCounterInstance.QuantizedMin[$t] -lt $Threshold)
                            {
                                $IsMinThresholdBroken = $True
                            }
                    	}
                        'le'
                        {
                            If ($oCounterInstance.QuantizedMin[$t] -le $Threshold)
                            {
                                $IsMinThresholdBroken = $True
                            }
                    	}
                    	'eq'
                        {
                            If ($oCounterInstance.QuantizedMin[$t] -eq $Threshold)
                            {
                                $IsMinThresholdBroken = $True
                            }
                    	}
                    	default
                        {
                            If ($oCounterInstance.QuantizedMin[$t] -gt $Threshold)
                            {
                                $IsMinThresholdBroken = $True
                            }                    
                    	}
                    }
                }
                #/////////////////////////
                #// IsAvgThresholdBroken
                #/////////////////////////
                If (($oCounterInstance.QuantizedAvg[$t] -ne '-') -and ($oCounterInstance.QuantizedAvg[$t] -ne $null))
                {
    				switch ($Operator)
                    {
                        'gt'
                        {
                            If ($oCounterInstance.QuantizedAvg[$t] -gt $Threshold)
                            {
                                $IsAvgThresholdBroken = $True
                            }
                    	}
                        'ge'
                        {
                            If ($oCounterInstance.QuantizedAvg[$t] -ge $Threshold)
                            {
                                $IsAvgThresholdBroken = $True
                            }
                    	}
                    	'lt'
                        {
                            If ($oCounterInstance.QuantizedAvg[$t] -lt $Threshold)
                            {
                                $IsAvgThresholdBroken = $True
                            }
                    	}
                        'le'
                        {
                            If ($oCounterInstance.QuantizedAvg[$t] -le $Threshold)
                            {
                                $IsAvgThresholdBroken = $True
                            }
                    	}
                    	'eq'
                        {
                            If ($oCounterInstance.QuantizedAvg[$t] -eq $Threshold)
                            {
                                $IsAvgThresholdBroken = $True
                            }
                    	}
                    	default
                        {
                            If ($oCounterInstance.QuantizedAvg[$t] -gt $Threshold)
                            {
                                $IsAvgThresholdBroken = $True
                            }                    
                    	}
                    }
                }            
                #/////////////////////////
                #// IsMaxThresholdBroken
                #/////////////////////////
                If (($oCounterInstance.QuantizedMax[$t] -ne '-') -and ($oCounterInstance.QuantizedMax[$t] -ne $null))
                {
    				switch ($Operator)
                    {
                        'gt'
                        {
                            If ($oCounterInstance.QuantizedMax[$t] -gt $Threshold)
                            {
                                $IsMaxThresholdBroken = $True
                            }
                    	}
                        'ge'
                        {
                            If ($oCounterInstance.QuantizedMax[$t] -ge $Threshold)
                            {
                                $IsMaxThresholdBroken = $True
                            }
                    	}
                    	'lt'
                        {
                            If ($oCounterInstance.QuantizedMax[$t] -lt $Threshold)
                            {
                                $IsMaxThresholdBroken = $True
                            }
                    	}
                        'le'
                        {
                            If ($oCounterInstance.QuantizedMax[$t] -le $Threshold)
                            {
                                $IsMaxThresholdBroken = $True
                            }
                    	}
                    	'eq'
                        {
                            If ($oCounterInstance.QuantizedMax[$t] -eq $Threshold)
                            {
                                $IsMaxThresholdBroken = $True
                            }
                    	}
                    	default
                        {
                            If ($oCounterInstance.QuantizedMax[$t] -gt $Threshold)
                            {
                                $IsMaxThresholdBroken = $True
                            }                    
                    	}
                    }
                }
            }
            Else
            {
                #/////////////////////////
                #// IsTrendThresholdBroken
                #/////////////////////////
                If (($oCounterInstance.QuantizedTrend[$t] -ne '-') -and ($oCounterInstance.QuantizedTrend[$t] -ne $null))
                {
    				switch ($Operator)
                    {
                        'gt'
                        {
                            If ($oCounterInstance.QuantizedTrend[$t] -gt $Threshold)
                            {
                                $IsTrendThresholdBroken = $True
                            }
                    	}
                        'ge'
                        {
                            If ($oCounterInstance.QuantizedTrend[$t] -ge $Threshold)
                            {
                                $IsTrendThresholdBroken = $True
                            }
                    	}
                    	'lt'
                        {
                            If ($oCounterInstance.QuantizedTrend[$t] -lt $Threshold)
                            {
                                $IsTrendThresholdBroken = $True
                            }
                    	}
                        'le'
                        {
                            If ($oCounterInstance.QuantizedTrend[$t] -le $Threshold)
                            {
                                $IsTrendThresholdBroken = $True
                            }
                    	}
                    	'eq'
                        {
                            If ($oCounterInstance.QuantizedTrend[$t] -eq $Threshold)
                            {
                                $IsTrendThresholdBroken = $True
                            }
                    	}
                    	default
                        {
                            If ($oCounterInstance.QuantizedTrend[$t] -gt $Threshold)
                            {
                                $IsTrendThresholdBroken = $True
                            }                    
                    	}
                    }
                }
            }
            If (($IsMinThresholdBroken -eq $True) -or ($IsAvgThresholdBroken -eq $True) -or ($IsMaxThresholdBroken -eq $True) -or ($IsTrendThresholdBroken -eq $True))
            {
                CreateAlert -TimeSliceIndex $t -CounterInstanceObject $oCounterInstance -IsMinThresholdBroken $IsMinThresholdBroken -IsAvgThresholdBroken $IsAvgThresholdBroken -IsMaxThresholdBroken $IsMaxThresholdBroken -IsTrendThresholdBroken $IsTrendThresholdBroken -IsMinEvaluated $IsMinEvaulated -IsAvgEvaluated $IsAvgEvaulated -IsMaxEvaluated $IsMaxEvaulated -IsTrendEvaluated $IsTrendEvaulated
            }
        }
    }
}

Function StaticTrendThreshold
{
    param($CollectionOfCounterInstances,$Operator,$Threshold,$IsTrendOnly=$False)
    StaticThreshold -CollectionOfCounterInstances $CollectionOfCounterInstances -Operator $Operator -Threshold $Threshold -IsTrendOnly $True
}




Function ProcessThreshold
{
    param($XmlAnalysisInstance,$XmlThreshold)
    
    $global:CurrentXmlAnalysisInstance = $XmlAnalysisInstance
    $global:ThresholdName = $XmlThreshold.NAME
    $global:ThresholdCondition = $XmlThreshold.CONDITION
    $global:ThresholdColor = $XmlThreshold.COLOR
    $global:ThresholdPriority = $XmlThreshold.PRIORITY
    If ($(Test-property -InputObject $XmlAnalysisInstance -Name 'ID') -eq $True)
    {
        $global:ThresholdAnalysisID = $XmlAnalysisInstance.ID
    }
    Else
    {
        $global:ThresholdAnalysisID = Get-GUID
    }
    
    
    ForEach ($XmlCode in $XmlThreshold.SelectNodes("./CODE"))
    {
		$sCode = $XmlCode.get_innertext()
		#'Code before changes:' >> CodeDebug.txt
		#'====================' >> CodeDebug.txt
		#$sCode >> CodeDebug.txt            
		#// Replace all of the variables with their hash table version.
		ForEach ($sKey in $htCodeReplacements.Keys)
		{
			$sCode = $sCode -Replace $sKey,$htCodeReplacements[$sKey]
		}
        
		#// Execute the code
		ExecuteCodeForThreshold -Code $sCode -Name $ThresholdName -htVariables $htVariables -htQuestionVariables $htQuestionVariables        
		Break #// Only execute one block of code, so breaking out.
    }
}

Function ExecuteCodeForThreshold
{
    param($Code,$Name,$htVariables,$htQuestionVariables)
    $global:IsMinThresholdBroken = $False
    $global:IsAvgThresholdBroken = $False
    $global:IsMaxThresholdBroken = $False
    $global:IsTrendThresholdBroken = $False
    $global:IsMinEvaluated = $False
    $global:IsAvgEvaluated = $False
    $global:IsMaxEvaluated = $False
    $global:IsTrendEvaluated = $False
    #'Code after changes:' >> CodeDebug.txt
    #'===================' >> CodeDebug.txt
    #$sCode >> CodeDebug.txt
    Invoke-Expression -Command $sCode
}


Function FillNullsWithDashesAndIsAllNull
{
    param($Values)
    For ($i=0;$i -le $Values.GetUpperBound(0);$i++)
    {
        If (($Values[$i] -eq ' ') -or ($Values[$i] -eq $null))
        {
            $Values[$i] = '-'
        }
        Else
        {
            $global:IsValuesAllNull = $False
        }
    }
    $Values
}

Function ProcessAnalysisInterval
{
    param($aTime)
    If ($Interval -eq 'AUTO')
    {
        $global:AnalysisInterval = GenerateAutoAnalysisInterval -ArrayOfTimes $aTime
    }
    Else
    {
        $global:AnalysisInterval = $Interval
    }
}

Function GenerateAutoAnalysisInterval
{
	param($ArrayOfTimes,$NumberOfTimeSlices=30)
	$iTimeSpanInSeconds = [int] $(New-TimeSpan -Start ([DateTime] $ArrayOfTimes[0]) -End ([DateTime] $ArrayOfTimes[$ArrayOfTimes.GetUpperBound(0)])).TotalSeconds
	[int] $AutoAnalysisIntervalInSeconds = $iTimeSpanInSeconds / $NumberOfTimeSlices
	$AutoAnalysisIntervalInSeconds
}


Function AddCounterInstancesToXmlDataSource($XmlDoc,$XmlDataSource,$sCounterPath,$sCounterComputer,$sCounterObject,$sCounterName,$sCounterInstance,$iCounterInstanceInCsv)
{
	If (($global:aTime -eq '') -or ($global:aTime -eq $null))
	{
		$global:aTime = GetTimeDataFromPerfmonLog
	}
    $global:IsValuesAllNull = $True
	$aValue = GetCounterDataFromPerfmonLog $sCounterPath $iCounterInstanceInCsv
    $aValue = FillNullsWithDashesAndIsAllNull -Values $aValue
    
    If ($global:IsAnalysisIntervalCalculated -eq $False)
    {
        ProcessAnalysisInterval $global:aTime
        $global:IsAnalysisIntervalCalculated = $True
    }
    
    If ($alQuantizedIndex -eq $null)
    {
        $global:alQuantizedIndex = @(GenerateQuantizedIndexArray -ArrayOfTimes $aTime -AnalysisIntervalInSeconds $global:AnalysisInterval)
    }
        
    If ($alQuantizedTime -eq $null)
    {
        $global:alQuantizedTime = @(GenerateQuantizedTimeArray -ArrayOfTimes $aTime -QuantizedIndexArray $alQuantizedIndex)
    }
    
    If ($global:IsValuesAllNull -eq $False)
    {        
        $MightBeArrayListOrDouble = $(MakeNumeric -Values $aValue)
        $alAllNumeric = New-Object System.Collections.ArrayList
        If (($MightBeArrayListOrDouble -is [System.Collections.ArrayList]) -or ($MightBeArrayListOrDouble -is [Array]))
        {
            [System.Collections.ArrayList] $alAllNumeric = $MightBeArrayListOrDouble
        }
        Else
        {        
            [void] $AlAllNumeric.Add($MightBeArrayListOrDouble)
        }
    	$alQuantizedAvgValues = @(GenerateQuantizedAvgValueArray -ArrayOfValues $alAllNumeric -ArrayOfQuantizedIndexes $alQuantizedIndex -DataTypeAsString $($XmlDataSource.DATATYPE))
    	$alQuantizedMinValues = @(GenerateQuantizedMinValueArray -ArrayOfValues $alAllNumeric -ArrayOfQuantizedIndexes $alQuantizedIndex -DataTypeAsString $($XmlDataSource.DATATYPE))
    	$alQuantizedMaxValues = @(GenerateQuantizedMaxValueArray -ArrayOfValues $alAllNumeric -ArrayOfQuantizedIndexes $alQuantizedIndex -DataTypeAsString $($XmlDataSource.DATATYPE))
    	$alQuantizedTrendValues = @(GenerateQuantizedTrendValueArray -ArrayOfQuantizedAvgs $alQuantizedAvgValues -AnalysisIntervalInSeconds $AnalysisInterval -DataTypeAsString $($XmlDataSource.DATATYPE))
            
        $oStats = $alAllNumeric | Measure-Object -Average -Minimum -Maximum
        $Min = $(ConvertToDataType -ValueAsDouble $oStats.Minimum -DataTypeAsString $XmlDataSource.DATATYPE)
        $Avg = $(ConvertToDataType -ValueAsDouble $oStats.Average -DataTypeAsString $XmlDataSource.DATATYPE)
        $Max = $(ConvertToDataType -ValueAsDouble $oStats.Maximum -DataTypeAsString $XmlDataSource.DATATYPE)
        $Trend = $(ConvertToDataType -ValueAsDouble $alQuantizedTrendValues[$($alQuantizedTrendValues.GetUpperBound(0))] -DataTypeAsString $XmlDataSource.DATATYPE)    
        $StdDev = $(CalculateStdDev -Values $alAllNumeric)
        $StdDev = $(ConvertToDataType -ValueAsDouble $StdDev -DataTypeAsString $XmlDataSource.DATATYPE)    
        $PercentileSeventyth = $(CalculatePercentile -Values $alAllNumeric -Percentile 70)
        $PercentileSeventyth = $(ConvertToDataType -ValueAsDouble $PercentileSeventyth -DataTypeAsString $XmlDataSource.DATATYPE)
        $PercentileEightyth = $(CalculatePercentile -Values $alAllNumeric -Percentile 80)
        $PercentileEightyth = $(ConvertToDataType -ValueAsDouble $PercentileEightyth -DataTypeAsString $XmlDataSource.DATATYPE)
        $PercentileNinetyth = $(CalculatePercentile -Values $alAllNumeric -Percentile 90)
        $PercentileNinetyth = $(ConvertToDataType -ValueAsDouble $PercentileNinetyth -DataTypeAsString $XmlDataSource.DATATYPE)    
    }
    Else
    {
    	$alQuantizedAvgValues = '-'
    	$alQuantizedMinValues = '-'
    	$alQuantizedMaxValues = '-'
    	$alQuantizedTrendValues = '-'
        
        $Min = '-'
        $Avg = '-'
        $Max = '-'
        $Trend = '-'
        $StdDev = '-'
        $StdDev = '-'
        $PercentileSeventyth = '-'
        $PercentileSeventyth = '-'
        $PercentileEightyth = '-'
        $PercentileEightyth = '-'
        $PercentileNinetyth = '-'
        $PercentileNinetyth = '-'
    }
    
    AddToCounterInstanceStatsArrayList $sCounterPath $aTime $aValue $alQuantizedTime $alQuantizedMinValues $alQuantizedAvgValues $alQuantizedMaxValues $alQuantizedTrendValues $sCounterComputer $sCounterObject $sCounterName $sCounterInstance $Min $Avg $Max $Trend $StdDev $PercentileSeventyth $PercentileEightyth $PercentileNinetyth

    $XmlNewCounterInstance = $XmlAnalysis.CreateElement("COUNTERINSTANCE")
    $XmlNewCounterInstance.SetAttribute("NAME", $sCounterPath)
    $XmlNewCounterInstance.SetAttribute("MIN", $([string]::Join(',',$Min)))
    $XmlNewCounterInstance.SetAttribute("AVG", $([string]::Join(',',$Avg)))
    $XmlNewCounterInstance.SetAttribute("MAX", $([string]::Join(',',$Max)))
    $XmlNewCounterInstance.SetAttribute("TREND", $([string]::Join(',',$Trend)))
    $XmlNewCounterInstance.SetAttribute("STDDEV", $([string]::Join(',',$StdDev)))
    $XmlNewCounterInstance.SetAttribute("PERCENTILESEVENTYTH", $([string]::Join(',',$PercentileSeventyth)))
    $XmlNewCounterInstance.SetAttribute("PERCENTILEEIGHTYTH", $([string]::Join(',',$PercentileEightyth)))
    $XmlNewCounterInstance.SetAttribute("PERCENTILENINETYTH", $([string]::Join(',',$PercentileNinetyth)))
    $XmlNewCounterInstance.SetAttribute("QUANTIZEDMIN", $([string]::Join(',',$alQuantizedMinValues)))
    $XmlNewCounterInstance.SetAttribute("QUANTIZEDAVG", $([string]::Join(',',$alQuantizedAvgValues)))
    $XmlNewCounterInstance.SetAttribute("QUANTIZEDMAX", $([string]::Join(',',$alQuantizedMaxValues)))
    $XmlNewCounterInstance.SetAttribute("QUANTIZEDTREND", $([string]::Join(',',$alQuantizedTrendValues)))
    $XmlNewCounterInstance.SetAttribute("COUNTERPATH", $sCounterPath)
    $XmlNewCounterInstance.SetAttribute("COUNTERCOMPUTER", $sCounterComputer)
    If (($($sCounterPath.Contains('MSSQL$')) -eq $True) -or ($($sCounterPath.Contains('MSOLAP$')) -eq $True))
    {
        $sCounterObject = GetCounterObject $sCounterPath
    }
    $XmlNewCounterInstance.SetAttribute("COUNTEROBJECT", $sCounterObject)
    $XmlNewCounterInstance.SetAttribute("COUNTERNAME", $sCounterName)
    $XmlNewCounterInstance.SetAttribute("COUNTERINSTANCE", $sCounterInstance)
    $XmlNewCounterInstance.SetAttribute("ISALLNULL", $global:IsValuesAllNull)
    [void] $XmlDataSource.AppendChild($XmlNewCounterInstance)    
}


Function IsNumeric
{
    param($Value)
    [double]$number = 0
    $result = [double]::TryParse($Value, [REF]$number)
    $result
}


Function ConvertToDataType
{
	param($ValueAsDouble, $DataTypeAsString="integer")
	$sDateType = $DataTypeAsString.ToLower()

    If ($(IsNumeric -Value $ValueAsDouble) -eq $True)
    {
    	switch ($sDateType)
    	{
    		#"absolute" {[Math]::Abs($ValueAsDouble)}
    		#"double" {[double]$ValueAsDouble}
    		"integer" {[Math]::Round($ValueAsDouble,0)}
    		#"long" {[long]$ValueAsDouble}
    		#"single" {[single]$ValueAsDouble}
    		"round1" {[Math]::Round($ValueAsDouble,1)}
    		"round2" {[Math]::Round($ValueAsDouble,2)}
    		"round3" {[Math]::Round($ValueAsDouble,3)}
    		"round4" {[Math]::Round($ValueAsDouble,4)}
    		"round5" {[Math]::Round($ValueAsDouble,5)}
    		"round6" {[Math]::Round($ValueAsDouble,6)}
    		default {$ValueAsDouble}
    	}
    }
    Else
    {
        $ValueAsDouble
    }
}



Function AddToCounterInstanceStatsArrayList
{
    param($sCounterPath,$aTime,$aValue,$alQuantizedTime,$alQuantizedMinValues,$alQuantizedAvgValues,$alQuantizedMaxValues,$alQuantizedTrendValues,$sCounterComputer,$sCounterObject,$sCounterName,$sCounterInstance, $Min='-', $Avg='-', $Max='-', $Trend='-', $StdDev='-', $PercentileSeventyth='-', $PercentileEightyth='-', $PercentileNinetyth='-')
        
    If ($htCounterInstanceStats.Contains($sCounterPath) -eq $False)
    {
    	$quantizedResultsObject = New-Object pscustomobject
    	Add-Member -InputObject $quantizedResultsObject -MemberType NoteProperty -Name CounterPath -Value $sCounterPath
        Add-Member -InputObject $quantizedResultsObject -MemberType NoteProperty -Name CounterComputer -Value $sCounterComputer
        #// Check if this is a SQL Named instance.
        If (($($sCounterPath.Contains('MSSQL$')) -eq $True) -or ($($sCounterPath.Contains('MSOLAP$')) -eq $True))
        {
            $sCounterObject = GetCounterObject $sCounterPath
        }
    	Add-Member -InputObject $quantizedResultsObject -MemberType NoteProperty -Name CounterObject -Value $sCounterObject
    	Add-Member -InputObject $quantizedResultsObject -MemberType NoteProperty -Name CounterName -Value $sCounterName
    	Add-Member -InputObject $quantizedResultsObject -MemberType NoteProperty -Name CounterInstance -Value $sCounterInstance
    	Add-Member -InputObject $quantizedResultsObject -MemberType NoteProperty -Name Time -Value $aTime
    	Add-Member -InputObject $quantizedResultsObject -MemberType NoteProperty -Name Value -Value $aValue
    	Add-Member -InputObject $quantizedResultsObject -MemberType NoteProperty -Name QuantizedTime -Value $alQuantizedTime
    	Add-Member -InputObject $quantizedResultsObject -MemberType NoteProperty -Name QuantizedMin -Value $alQuantizedMinValues
    	Add-Member -InputObject $quantizedResultsObject -MemberType NoteProperty -Name QuantizedAvg -Value $alQuantizedAvgValues
    	Add-Member -InputObject $quantizedResultsObject -MemberType NoteProperty -Name QuantizedMax -Value $alQuantizedMaxValues
        Add-Member -InputObject $quantizedResultsObject -MemberType NoteProperty -Name QuantizedTrend -Value $alQuantizedTrendValues
    	Add-Member -InputObject $quantizedResultsObject -MemberType NoteProperty -Name Min -Value $Min
        Add-Member -InputObject $quantizedResultsObject -MemberType NoteProperty -Name Avg -Value $Avg
        Add-Member -InputObject $quantizedResultsObject -MemberType NoteProperty -Name Max -Value $Max
        Add-Member -InputObject $quantizedResultsObject -MemberType NoteProperty -Name Trend -Value $Trend
        Add-Member -InputObject $quantizedResultsObject -MemberType NoteProperty -Name StdDev -Value $StdDev
        Add-Member -InputObject $quantizedResultsObject -MemberType NoteProperty -Name PercentileSeventyth -Value $PercentileSeventyth
        Add-Member -InputObject $quantizedResultsObject -MemberType NoteProperty -Name PercentileEightyth -Value $PercentileEightyth
        Add-Member -InputObject $quantizedResultsObject -MemberType NoteProperty -Name PercentileNinetyth -Value $PercentileNinetyth
    	[void] $htCounterInstanceStats.Add($sCounterPath,$quantizedResultsObject)
    }
}



Function GenerateQuantizedIndexArray
{
	param($ArrayOfTimes,$AnalysisIntervalInSeconds=60)
	$alIndexArray = New-Object System.Collections.ArrayList
	$alSubIndexArray = New-Object System.Collections.ArrayList
	[datetime] $dTimeCursor = [datetime] $ArrayOfTimes[0]
	$dTimeCursor = $dTimeCursor.AddSeconds($AnalysisIntervalInSeconds)
    $u = $ArrayOfTimes.GetUpperBound(0)
    $dEndTime = [datetime] $ArrayOfTimes[$u]
    
    #// If the analysis interval is larger than the entire time range of the log, then just use the one time slice.
    If ($dTimeCursor -gt $dEndTime)
    {
        $dDurationTime = New-TimeSpan -Start $ArrayOfTimes[0] -End $dEndTime
        Write-Warning $('The analysis interval is larger than the time range of the entire log. Please use an analysis interval that is smaller than ' + "$($dDurationTime.TotalSeconds)" + ' seconds.')
        Write-Warning $("Log Start Time: $($ArrayOfTimes[0])")
        Write-Warning $("Log Stop Time: $($ArrayOfTimes[$u])")
        Write-Warning $("Log Length: $($dDurationTime)")
        Break Main;
    }
    
    #// Set the Chart X Axis interval
    If ($global:NumberOfValuesPerTimeSlice -eq -1)
    {
    	:ValuesPerTimeSliceLoop For ($i=0;$i -le $ArrayOfTimes.GetUpperBound(0);$i++)
    	{
    		If ($ArrayOfTimes[$i] -le $dTimeCursor)
    		{
    			[Void] $alSubIndexArray.Add($i)
                $global:NumberOfValuesPerTimeSlice = $alSubIndexArray.Count
    		}
    		Else
    		{
                $global:NumberOfValuesPerTimeSlice = $alSubIndexArray.Count
    			$alSubIndexArray.Clear()
                Break ValuesPerTimeSliceLoop;
    		}
    	}
        $global:CHART_AXIS_X_INTERVAL = $global:NumberOfValuesPerTimeSlice        
        $iNumberOfValuesPerTimeSliceInChart = $global:NumberOfValuesPerTimeSlice
        $iNumberOfIntervals = $ArrayOfTimes.Count / $global:NumberOfValuesPerTimeSlice
        $iNumberOfIntervals = [Math]::Round($iNumberOfIntervals,0)
        If ($iNumberOfIntervals -gt $global:CHART_MAX_NUMBER_OF_AXIS_X_INTERVALS)
        {
            $iNumberOfValuesPerTimeSliceInChart = $ArrayOfTimes.Count / $global:CHART_MAX_NUMBER_OF_AXIS_X_INTERVALS
            $iNumberOfValuesPerTimeSliceInChart = [Math]::Round($iNumberOfValuesPerTimeSliceInChart,0)
            $global:CHART_AXIS_X_INTERVAL = $iNumberOfValuesPerTimeSliceInChart
        }
    }    
    
    #// Quantize the time array.
	For ($i=0;$i -le $ArrayOfTimes.GetUpperBound(0);$i++)
	{
		If ($ArrayOfTimes[$i] -le $dTimeCursor)
		{
			[Void] $alSubIndexArray.Add($i)
		}
		Else
		{
			[Void] $alIndexArray.Add([System.Object[]] $alSubIndexArray)
			$alSubIndexArray.Clear()
			[Void] $alSubIndexArray.Add($i)
			$dTimeCursor = $dTimeCursor.AddSeconds($AnalysisIntervalInSeconds)
		}
	}	
	$alIndexArray
}

Function GenerateQuantizedTimeArray
{
	param($ArrayOfTimes,$QuantizedIndexArray = $(GenerateQuantizedIndexArray -ArrayOfTimes $ArrayOfTimes -AnalysisIntervalInSeconds $global:AnalysisInterval))
	$alQuantizedTimeArray = New-Object System.Collections.ArrayList
	For ($i=0;$i -lt $QuantizedIndexArray.Count;$i++)
	{
		$iFirstIndex = $QuantizedIndexArray[$i][0]
		[void] $alQuantizedTimeArray.Add([datetime]$ArrayOfTimes[$iFirstIndex])	
	}
	$alQuantizedTimeArray
}

Function GenerateQuantizedAvgValueArray
{
	param($ArrayOfValues, $ArrayOfQuantizedIndexes, $DataTypeAsString="double")
	$aAvgQuantizedValues = New-Object System.Collections.ArrayList
    If ($ArrayOfValues -is [System.Collections.ArrayList])
    {
        [boolean] $IsValueNumeric = $false
    	For ($a=0;$a -lt $ArrayOfQuantizedIndexes.Count;$a++)
    	{
    		[double] $iSum = 0.0
            [int] $iCount = 0
    		[System.Object[]] $aSubArray = $ArrayOfQuantizedIndexes[$a]
    		For ($b=0;$b -le $aSubArray.GetUpperBound(0);$b++)
    		{
    			$i = $aSubArray[$b]
                $IsValueNumeric = IsNumeric -Value $ArrayOfValues[$i]
                If ($IsValueNumeric)
                {
                    $iSum += $ArrayOfValues[$i]
                    $iCount++
                }			
    		}
            If ($iCount -gt 0)
            {
                $iValue = ConvertToDataType -ValueAsDouble $($iSum / $iCount) -DataTypeAsString $DataTypeAsString
                [Void] $aAvgQuantizedValues.Add($iValue)
            }
            Else
            {
                [Void] $aAvgQuantizedValues.Add('-')
            }
    	}
    }
    Else
    {
        Return $ArrayOfValues
    }
	$aAvgQuantizedValues
}

Function GenerateQuantizedMinValueArray
{
	param($ArrayOfValues, $ArrayOfQuantizedIndexes, $DataTypeAsString="double")
	$aMinQuantizedValues = New-Object System.Collections.ArrayList
    If ($ArrayOfValues -is [System.Collections.ArrayList])
    {
    	For ($a=0;$a -lt $ArrayOfQuantizedIndexes.Count;$a++)
    	{
            [int] $iCount = 0
    		[System.Object[]] $aSubArray = $ArrayOfQuantizedIndexes[$a]
    		$iMin = $ArrayOfValues[$aSubArray[0]]
    		For ($b=0;$b -le $aSubArray.GetUpperBound(0);$b++)
    		{
    			$i = $aSubArray[$b]
    			If ($ArrayOfValues[$i] -lt $iMin)
    			{
    				$iMin = $ArrayOfValues[$i]
                    #$iCount++
    			}
    		}
    		$iValue = ConvertToDataType -ValueAsDouble $iMin -DataTypeAsString $DataTypeAsString
    		[Void] $aMinQuantizedValues.Add($iValue)
    	}
    }
    Else
    {
        Return $ArrayOfValues
    }
	$aMinQuantizedValues
}

Function GenerateQuantizedMaxValueArray
{
	param($ArrayOfValues, $ArrayOfQuantizedIndexes, $DataTypeAsString="double")
	$aMaxQuantizedValues = New-Object System.Collections.ArrayList
    If ($ArrayOfValues -is [System.Collections.ArrayList])
    {
    	For ($a=0;$a -lt $ArrayOfQuantizedIndexes.Count;$a++)
    	{
            [int] $iCount = 0
    		[System.Object[]] $aSubArray = $ArrayOfQuantizedIndexes[$a]
    		$iMax = $ArrayOfValues[$aSubArray[0]]
    		For ($b=0;$b -le $aSubArray.GetUpperBound(0);$b++)
    		{
    			$i = $aSubArray[$b]
    			If ($ArrayOfValues[$i] -gt $iMax)
    			{
    				$iMax = $ArrayOfValues[$i]
                    #$iCount++
    			}
    		}
            $iValue = ConvertToDataType -ValueAsDouble $iMax -DataTypeAsString $DataTypeAsString
            [Void] $aMaxQuantizedValues.Add($iValue)
    	}
    }
    Else
    {
        Return $ArrayOfValues
    }
	$aMaxQuantizedValues
}

Function CalculateStdDev
{
	param($Values)
    $SumSquared = 0
	For ($i=0;$i -lt $Values.Count;$i++)
	{
		$SumSquared = $SumSquared + ($Values[$i] * $Values[$i])
	}	
	$oStats = $Values | Measure-Object -Sum
	
	If ($oStats.Sum -gt 0)
	{
		If ($oStats.Count -gt 1)
		{
			$StdDev = [Math]::Sqrt([Math]::Abs(($SumSquared - ($oStats.Sum * $oStats.Sum / $oStats.Count)) / ($oStats.Count -1)))
		}
		Else
		{
			$StdDev = [Math]::Sqrt([Math]::Abs(($SumSquared - ($oStats.Sum * $oStats.Sum / $oStats.Count)) / $oStats.Count))
		}
	}
	Else
	{
		$StdDev = 0
	}
	$StdDev
}

Function CalculatePercentile
{
	param($Values,$Percentile)
    If ($Values -eq $null)
    {Return $Values}
    If ($Values -is [System.Collections.ArrayList])
    {
    	$oStats = $Values | Measure-Object -Average -Minimum -Maximum -Sum
    	$iDeviation = $oStats.Average * ($Percentile / 100)
    	$iLBound = $Values.Count - [int]$(($Percentile / 100) * $Values.Count)
        $iUBound = [int]$(($Percentile / 100) * $Values.Count)
        [System.Object[]] $aSortedNumbers = $Values | Sort-Object
        If ($aSortedNumbers -isnot [System.Object[]])
        {
            Write-Error 'ERROR: $aSortedNumbers -isnot [System.Object[]]. This is most likely due to no counters in the threshold file matching to counters in the counter log.'
        }        
        $iIndex = 0
        If ($iUBound -gt $aSortedNumbers.GetUpperBound(0))
    	{
            $iUBound = $aSortedNumbers.GetUpperBound(0)
    	}
        If ($iLBound -eq $iUBound)
    	{
            Return $aSortedNumbers[$iLBound]
        }
    	$aNonDeviatedNumbers = New-Object System.Collections.ArrayList
        For ($i=0;$i -lt $iUBound;$i++)
    	{
            [void] $aNonDeviatedNumbers.Add($iIndex)
            $aNonDeviatedNumbers[$iIndex] = $aSortedNumbers[$i]
            $iIndex++
        }
        If ($iIndex -gt 0)
    	{
    		$oStats = $aNonDeviatedNumbers | Measure-Object -Average
            Return $oStats.Average
    	}
        Else
    	{
            Return "-"
        }
    }
    Else
    {
        Return $Values
    }
}


Function ConvertCounterArraysToSeriesHashTable
{
    param($alSeries, $aDateTimes, $htOfCounterValues)
    
	ConvertCounterArraysToSeriesHashTable $alSeries, $aDateTimes, $htOfCounterValues, $False
}


Function CalculateHourlyTrend
{
	param($Value,$AnalysisIntervalInSeconds,$DataTypeAsString)
    	
    If ($AnalysisIntervalInSeconds -lt 3600)
	{
        $IntervalAdjustment = 3600 / $AnalysisIntervalInSeconds 
        Return ConvertToDataType -ValueAsDouble $($Value * $IntervalAdjustment) -DataTypeAsString $DataTypeAsString
    }

    If ($AnalysisIntervalInSeconds -gt 3600)
	{
        $IntervalAdjustment = $AnalysisIntervalInSeconds / 3600
        Return ConvertToDataType -ValueAsDouble $($Value / $IntervalAdjustment) -DataTypeAsString $DataTypeAsString
    }

    If ($AnalysisIntervalInSeconds -eq 3600)
	{
        Return ConvertToDataType -ValueAsDouble $Value -DataTypeAsString $DataTypeAsString
	}
}


Function GetTimeZoneFromCsvFile
{
    param($CsvFilePath)
    
	$oCSVFile = Get-Content $CsvFilePath
	$aRawCounterList = $oCSVFile[0].Split(",")
	Return $aRawCounterList[0].Trim("`"")
}


Function GetTimeDataFromPerfmonLog()
{
	If ($global:sPerfLogTimeZone -eq "")
	{
		$global:sPerfLogTimeZone = GetTimeZoneFromCsvFile $global:sPerfLogFilePath
	}
    $global:aTime = GetCounterDataFromPerfmonLog -sCounterPath $global:sPerfLogTimeZone -iCounterIndexInCsv 0
    $global:aTime
}

Function CalculatePercentage
{
    param($Number,$Total)
    If ($Total -eq 0)
    {
        Return 100
    }
    $Result = ($Number * 100) / $Total
    $Result
}


Function ConstructCounterDataArray
{
    $PercentComplete = 0
#    write-progress -activity 'Importing counter data into memory...' -status '% Complete:' -percentcomplete $PercentComplete
    
	$oCSVFile = Get-Content -Path $global:sPerfLogFilePath
	#// Get the width and height of the CSV file as indexes.
	$aLine = $oCSVFile[0].Trim('"') -split '","'
    $iPerfmonCsvIndexWidth = $aLine.GetUpperBound(0)
	$iPerfmonCsvIndexHeight = $oCSVFile.GetUpperBound(0)
	$global:alCounterData = New-Object System.Collections.ArrayList
	If ($($oCSVFile[$iPerfmonCsvIndexHeight].Contains(',')) -eq $False)
	{
		do 
		{
			$iPerfmonCsvIndexHeight = $iPerfmonCsvIndexHeight - 1
		} until ($($oCSVFile[$iPerfmonCsvIndexHeight].Contains(',')) -eq $true)	
	}
	For ($i=0;$i -le $iPerfmonCsvIndexHeight;$i++)
	{
		$aLine = $oCSVFile[$i].Trim('"') -split '","'
		[void] $global:alCounterData.Add($aLine)
#        $PercentComplete = CalculatePercentage -Number $i -Total $iPerfmonCsvIndexHeight
#        write-progress -activity 'Importing counter data into memory...' -status '% Complete:' -percentcomplete $PercentComplete
	}
	$global:alCounterData
#    write-progress -activity 'Importing counter data into memory...' -status '% Complete:' -Completed
}




Function GetCounterDataFromPerfmonLog($sCounterPath,$iCounterIndexInCsv)
{    
    $aValues = New-Object System.Collections.ArrayList
    If ($global:alCounterData -eq $null)
    {
        $global:alCounterData = ConstructCounterDataArray
    }
    
    For ($i=1;$i -lt $global:alCounterData.Count;$i++)
    {
        [void] $aValues.Add($($global:alCounterData[$i][$iCounterIndexInCsv]))
    }
	$aValues
}


Function GenerateQuantizedArrayListForOverallStats
{
    param($Value)
    $alCounterStats = New-Object System.Collections.ArrayList
    If ($(IsNumeric -Value $Value) -eq $True)
    {
        [double] $Value = $Value
    }    
    For ($t=0;$t -lt $alQuantizedTime.Count;$t++)
    {
        If ($t -eq 0)
        {
            [void] $alCounterStats.Add($Value)
        }
        Else
        {
            [void] $alCounterStats.Add('-')
        }
    }
    $alCounterStats
}


Function PrepareEnvironmentForThresholdProcessing
{
    param($CurrentAnalysisInstance)
    
    If ($alQuantizedIndex -eq $null)
    {
        If (($aTime -eq $null) -or ($aTime -eq ''))
        {
            $aTime = GetTimeDataFromPerfmonLog
        }
        $alQuantizedIndex = GenerateQuantizedIndexArray -ArrayOfTimes $aTime -AnalysisIntervalInSeconds $AnalysisInterval
    }
    
    If ($global:alQuantizedTime -eq $null)
    {
        $global:alQuantizedTime = GenerateQuantizedTimeArray -ArrayOfTimes $aTime -QuantizedIndexArray $alQuantizedIndex
    }
    
    #// Create an internal overall counter stat for each counter instance for each counter stat.
    ForEach ($XmlDataSource in $CurrentAnalysisInstance.SelectNodes('./DATASOURCE'))
    {
        ForEach ($XmlCounterInstance in $XmlDataSource.SelectNodes('./COUNTERINSTANCE'))
        {
            If ($(Test-XmlBoolAttribute -InputObject $XmlCounterInstance -Name 'ISINTERNALONLY') -eq $True)
            {
                $IsInternalOnly = $True
            }
            Else
            {
                $IsInternalOnly = $False
            }
            If ($IsInternalOnly -eq $False)
            {
                $XmlNewCounterInstance = $XmlAnalysis.CreateElement("COUNTERINSTANCE")
                $InternalCounterInstanceName = 'INTERNAL_OVERALL_COUNTER_STATS_' + $($XmlCounterInstance.NAME)
                $XmlNewCounterInstance.SetAttribute("NAME", $InternalCounterInstanceName)
                $XmlNewCounterInstance.SetAttribute("MIN", $($XmlCounterInstance.MIN))
                $XmlNewCounterInstance.SetAttribute("AVG", $($XmlCounterInstance.AVG))
                $XmlNewCounterInstance.SetAttribute("MAX", $($XmlCounterInstance.MAX))
                $XmlNewCounterInstance.SetAttribute("TREND", $($XmlCounterInstance.TREND))
                $XmlNewCounterInstance.SetAttribute("STDDEV", $($XmlCounterInstance.STDDEV))
                $XmlNewCounterInstance.SetAttribute("PERCENTILESEVENTYTH", $($XmlCounterInstance.PERCENTILESEVENTYTH))
                $XmlNewCounterInstance.SetAttribute("PERCENTILEEIGHTYTH", $($XmlCounterInstance.PERCENTILEEIGHTYTH))
                $XmlNewCounterInstance.SetAttribute("PERCENTILENINETYTH", $($XmlCounterInstance.PERCENTILENINETYTH))
                $QuantizedMinForOverallStats = GenerateQuantizedArrayListForOverallStats -Value $XmlCounterInstance.MIN
                $QuantizedAvgForOverallStats = GenerateQuantizedArrayListForOverallStats -Value $XmlCounterInstance.AVG
                $QuantizedMaxForOverallStats = GenerateQuantizedArrayListForOverallStats -Value $XmlCounterInstance.MAX
                $QuantizedTrendForOverallStats = GenerateQuantizedArrayListForOverallStats -Value $XmlCounterInstance.TREND
                $XmlNewCounterInstance.SetAttribute("QUANTIZEDMIN", $([string]::Join(',',$QuantizedMinForOverallStats)))
                $XmlNewCounterInstance.SetAttribute("QUANTIZEDAVG", $([string]::Join(',',$QuantizedAvgForOverallStats)))
                $XmlNewCounterInstance.SetAttribute("QUANTIZEDMAX", $([string]::Join(',',$QuantizedMaxForOverallStats)))
                $XmlNewCounterInstance.SetAttribute("QUANTIZEDTREND", $([string]::Join(',',$QuantizedTrendForOverallStats)))
                $XmlNewCounterInstance.SetAttribute("COUNTERPATH", $($XmlCounterInstance.COUNTERPATH))
                $XmlNewCounterInstance.SetAttribute("COUNTERCOMPUTER", $($XmlCounterInstance.COUNTERCOMPUTER))
                $XmlNewCounterInstance.SetAttribute("COUNTEROBJECT", $($XmlCounterInstance.COUNTEROBJECT))
                $XmlNewCounterInstance.SetAttribute("COUNTERNAME", $($XmlCounterInstance.COUNTERNAME))
                If ($(Test-property -InputObject $XmlCounterInstance -Name 'ISALLNULL') -eq $True)
                {
                    $XmlNewCounterInstance.SetAttribute("ISALLNULL", $($XmlCounterInstance.ISALLNULL))
                }
                Else
                {
                    $XmlNewCounterInstance.SetAttribute("ISALLNULL", 'False')
                }                    
                $XmlNewCounterInstance.SetAttribute("ISINTERNALONLY", $True)
                $XmlNewCounterInstance.SetAttribute("ORIGINALNAME", $($XmlCounterInstance.NAME))
                [void] $XmlDataSource.AppendChild($XmlNewCounterInstance)
                $oCounter = $htCounterInstanceStats[$XmlCounterInstance.NAME]
                AddToCounterInstanceStatsArrayList $InternalCounterInstanceName $oCounter.Time $oCounter.Value $oCounter.QuantizedTime $QuantizedMinForOverallStats $QuantizedAvgForOverallStats $QuantizedMaxForOverallStats $QuantizedTrendForOverallStats $oCounter.CounterComputer $oCounter.CounterObject $oCounter.CounterName $oCounter.CounterInstance $oCounter.Min $oCounter.Avg $oCounter.Max $oCounter.Trend $oCounter.StdDev $oCounter.PercentileSeventyth $oCounter.PercentileEightyth $oCounter.PercentileNinetyth
                [void] $htVariables[$($XmlDataSource.COLLECTIONVARNAME)].Add($htCounterInstanceStats[$InternalCounterInstanceName])
            }
        }
    }
}

Function SetXmlChartIsThresholdAddedAttribute
{
    param($XmlChart)
    [Int] $iNumOfSeries = 0
    
    ForEach ($XmlChartSeries in $XmlChart.SelectNodes("./SERIES"))
    {
        $iNumOfSeries++
    }
    
    If ($iNumOfSeries -eq 0)
    {
        $XmlChart.SetAttribute("ISTHRESHOLDSADDED", "False")
    }
    Else
    {
        $XmlChart.SetAttribute("ISTHRESHOLDSADDED", "True")
    }
}


Function ExecuteCodeForGeneratedDataSource
{
    param($Code,$Name,$ExpressionPath,$htVariables,$htQuestionVariables)
    #'Code after changes:' >> CodeDebug.txt
    #'===================' >> CodeDebug.txt
    #$sCode >> CodeDebug.txt
    Invoke-Expression -Command $sCode
}


Function AddWarningCriticalThresholdRangesToXml
{
	param($XmlChartInstance,$WarningMinValues=$null,$WarningMaxValues=$null,$CriticalMinValues=$null,$CriticalMaxValues=$null)
	
    If (($WarningMinValues -ne $null) -or ($WarningMaxValues -ne $null))
    {
    	$oMinWarningStats = $WarningMinValues | Measure-Object -Minimum
    	$oMaxWarningStats = $WarningMaxValues | Measure-Object -Maximum
    	$XmlChartInstance.SetAttribute("MINWARNINGVALUE",$($oMinWarningStats.Minimum))
    	$XmlChartInstance.SetAttribute("MAXWARNINGVALUE",$($oMaxWarningStats.Maximum))        
    }
    
    If (($CriticalMinValues -ne $null) -or ($CriticalMaxValues -ne $null))
    {
    	$oMinCriticalStats = $CriticalMinValues | Measure-Object -Minimum
    	$oMaxCriticalStats = $CriticalMaxValues | Measure-Object -Maximum
    	$XmlChartInstance.SetAttribute("MINCRITICALVALUE",$($oMinCriticalStats.Minimum))
    	$XmlChartInstance.SetAttribute("MAXCRITICALVALUE",$($oMaxCriticalStats.Maximum))
    }
}


Function ExtractSqlNamedInstanceFromCounterObjectPath
{
    param($sCounterObjectPath)
    $sSqlNamedInstance = ''
    $iLocOfSqlInstance = $sCounterObjectPath.IndexOf('$')
    If ($iLocOfSqlInstance -eq -1)
    {
        Return $sSqlNamedInstance
    }
    $iLocOfSqlInstance++
    $iLocOfColon = $sCounterObjectPath.IndexOf(':',$iLocOfSqlInstance)
    $iLenOfSqlInstance = $iLocOfColon - $iLocOfSqlInstance
    $sSqlNamedInstance = $sCounterObjectPath.SubString($iLocOfSqlInstance,$iLenOfSqlInstance)
    Return $sSqlNamedInstance
}

Function AddADashStyle
{
    param($Series,$DashStyleNumber)
    
    If ($DashStyleNumber -gt 3)
    {
        do 
        {
        	$DashStyleNumber = $DashStyleNumber - 4
        } until ($DashStyleNumber -le 3)
    }
    
    switch ($DashStyleNumber)
    {
    	0 {$Series.BorderDashStyle = [System.Windows.Forms.DataVisualization.Charting.ChartDashStyle]"Solid"}
        1 {$Series.BorderDashStyle = [System.Windows.Forms.DataVisualization.Charting.ChartDashStyle]"Dash"}
    	2 {$Series.BorderDashStyle = [System.Windows.Forms.DataVisualization.Charting.ChartDashStyle]"DashDot"}
    	3 {$Series.BorderDashStyle = [System.Windows.Forms.DataVisualization.Charting.ChartDashStyle]"Dot"}
    	#4 {$Series.BorderDashStyle = [System.Windows.Forms.DataVisualization.Charting.ChartDashStyle]"Dot"}		
		default {$Series.BorderDashStyle = [System.Windows.Forms.DataVisualization.Charting.ChartDashStyle]"Solid"}
    }
	$Series
}



Function ConvertCounterArraysToSeriesHashTable
{
    param($alSeries, $aDateTimes, $htOfCounterValues, $IsThresholdsEnabled, $dWarningMin, $dWarningMax, $dCriticalMin, $dCriticalMax, $sBackGradientStyle="TopBottom")

	#[Void] [Reflection.Assembly]::LoadFile("C:\Program Files (x86)\Microsoft Chart Controls\Assemblies\System.Windows.Forms.DataVisualization.dll")

	If ($IsThresholdsEnabled -eq $True)
	{
        If ($dWarningMax -ne $null)
        {
    		#// Add Warning Threshold values
    		$SeriesWarningThreshold = New-Object System.Windows.Forms.DataVisualization.Charting.Series
    		For ($a=0; $a -lt $aDateTimes.length; $a++)
    		{
                If ($sBackGradientStyle -eq "BottomTop")
                {
                    [Void] $SeriesWarningThreshold.Points.Add($dWarningMax[$a], $dWarningMin[$a])
                }
                Else
                {
                    [Void] $SeriesWarningThreshold.Points.Add($dWarningMin[$a], $dWarningMax[$a])
                }
    		}
    		$SeriesWarningThreshold.ChartType = [System.Windows.Forms.DataVisualization.Charting.SeriesChartType]"Range"
    		$SeriesWarningThreshold.Name = "Warning"
            If ($sBackGradientStyle -eq "BottomTop")
            {
        		$SeriesWarningThreshold.Color = [System.Drawing.Color]"Transparent"
                $SeriesWarningThreshold.BackImageTransparentColor = [System.Drawing.Color]"White"
                $SeriesWarningThreshold.BackSecondaryColor = [System.Drawing.Color]"PaleGoldenrod"        
                $SeriesWarningThreshold.BackGradientStyle = [System.Windows.Forms.DataVisualization.Charting.GradientStyle]"TopBottom"
            }
            Else
            {
                $SeriesWarningThreshold.Color = [System.Drawing.Color]"PaleGoldenrod"
                $SeriesWarningThreshold.BackGradientStyle = [System.Windows.Forms.DataVisualization.Charting.GradientStyle]"TopBottom"
            }
    		#$SeriesWarningThreshold.BackHatchStyle = [System.Windows.Forms.DataVisualization.Charting.ChartHatchStyle]"Percent60"
    		[Void] $alSeries.Add($SeriesWarningThreshold)        
        }
        
        If ($dCriticalMin -ne $null)
        {
    		#// Add Critical Threshold values
    		$SeriesCriticalThreshold = New-Object System.Windows.Forms.DataVisualization.Charting.Series
    		For ($a=0; $a -lt $aDateTimes.length; $a++)
    		{
    			[Void] $SeriesCriticalThreshold.Points.Add($dCriticalMin[$a], $dCriticalMax[$a])
    		}
    		$SeriesCriticalThreshold.ChartType = [System.Windows.Forms.DataVisualization.Charting.SeriesChartType]"Range"
    		$SeriesCriticalThreshold.Name = "Critical"
            If ($sBackGradientStyle -eq "BottomTop")
            {
        		$SeriesCriticalThreshold.Color = [System.Drawing.Color]"Transparent"
                $SeriesCriticalThreshold.BackImageTransparentColor = [System.Drawing.Color]"White"
                $SeriesCriticalThreshold.BackSecondaryColor = [System.Drawing.Color]"Tomato"        
                $SeriesCriticalThreshold.BackGradientStyle = [System.Windows.Forms.DataVisualization.Charting.GradientStyle]"TopBottom"
            }
            Else
            {
                $SeriesCriticalThreshold.Color = [System.Drawing.Color]"Tomato"
                $SeriesCriticalThreshold.BackGradientStyle = [System.Windows.Forms.DataVisualization.Charting.GradientStyle]"TopBottom"
            }        
            [Void] $alSeries.Add($SeriesCriticalThreshold)
        }
	}
	#// Sort the hast table and return an array of dictionary objects
	[System.Object[]] $aDictionariesOfCounterValues = $htOfCounterValues.GetEnumerator() | Sort-Object Name
		
	#// Add the counter instance values
    If ($aDictionariesOfCounterValues -isnot [System.Object[]])
    {
#        Write-Host "Stop here"
    }
    
	For ($a=0; $a -lt $aDictionariesOfCounterValues.Count; $a++)
	{
		$SeriesOfCounterValues = New-Object System.Windows.Forms.DataVisualization.Charting.Series
        $aValues = $aDictionariesOfCounterValues[$a].Value
		For ($b=0;$b -lt $aValues.Count; $b++)
		{
			If (($aDateTimes[$b] -ne $null) -and ($aValues[$b] -ne $null))
			{
				## Updated to provide localised date time on charts JonnyG 2010-06-11
				#[Void] $SeriesOfCounterValues.Points.AddXY($aDateTimes[$b], $aValues[$b])
				[Void] $SeriesOfCounterValues.Points.AddXY(([datetime]$aDateTimes[$b]).tostring($global:sDateTimePattern), $aValues[$b])
			}
		}
		$SeriesOfCounterValues.ChartType = [System.Windows.Forms.DataVisualization.Charting.SeriesChartType]"Line"
		$SeriesOfCounterValues.Name = $aDictionariesOfCounterValues[$a].Name
        $SeriesOfCounterValues = AddADashStyle -Series $SeriesOfCounterValues -DashStyleNumber $a
        #// Line thickness
        $SeriesOfCounterValues.BorderWidth = $CHART_LINE_THICKNESS

		[Void] $alSeries.Add($SeriesOfCounterValues)
	}
}

Function ConvertCounterToFileName
{
    param($sCounterPath)
    
	$sCounterObject = GetCounterObject $sCounterPath
	$sCounterName = GetCounterName $sCounterPath
	$sResult = $sCounterObject + "_" + $sCounterName
	$sResult = $sResult -replace "/", "_"
	$sResult = $sResult -replace "%", "Percent"
	$sResult = $sResult -replace " ", "_"
	$sResult = $sResult -replace "\.", ""
	$sResult = $sResult -replace ":", "_"
	$sResult = $sResult -replace ">", "_"
	$sResult = $sResult -replace "<", "_"
	$sResult = $sResult -replace "\(", "_"
	$sResult = $sResult -replace "\)", "_"
	$sResult = $sResult -replace "\*", "x"
	$sResult = $sResult -replace "\|", "_"
    $sResult = $sResult -replace "#", "Num"
   	$sResult = $sResult -replace "\\", "_"
	$sResult = $sResult -replace "\?", ""
	$sResult = $sResult -replace "\*", ""
	$sResult = $sResult -replace "\|", "_"
	$sResult = $sResult -replace "{", ""
	$sResult = $sResult -replace "}", ""    
	Return $sResult
}


Function GenerateMSChart
{
    param($sChartTitle, $sSaveFilePath, $htOfSeriesObjects)
    
	#// GAC the Microsoft Chart Controls just in case it is not GAC'd.
	#// Requires the .NET Framework v3.5 Service Pack 1 or greater.
	#[Void] [Reflection.Assembly]::LoadFile("C:\Program Files (x86)\Microsoft Chart Controls\Assemblies\System.Windows.Forms.DataVisualization.dll")
	
	$oPALChart = New-Object System.Windows.Forms.DataVisualization.Charting.Chart
	$oPALChartArea = New-Object System.Windows.Forms.DataVisualization.Charting.ChartArea
	$fontNormal = new-object System.Drawing.Font("Tahoma",10,[Drawing.FontStyle]'Regular')

	$sFormat = "#" + $global:htScript["LocalizedThousandsSeparator"] + "###" + $global:htScript["LocalizedDecimal"] + "###"
    #$sFormat >> 'C:\Users\clinth\Documents\~MyDocs\output.txt'
	$oPALChartArea.AxisY.LabelStyle.Format = $sFormat
    #$fontNormal >> 'C:\Users\clinth\Documents\~MyDocs\output.txt'
	$oPALChartArea.AxisY.LabelStyle.Font = $fontNormal
	$oPALChartArea.AxisX.LabelStyle.Angle = 90
    #$global:CHART_AXIS_X_INTERVAL >> 'C:\Users\clinth\Documents\~MyDocs\output.txt'
    $oPALChartArea.AxisX.Interval = $global:CHART_AXIS_X_INTERVAL
    #$oPALChartArea.GetType().FullName >> 'C:\Users\clinth\Documents\~MyDocs\output.txt'
	$oPALChart.ChartAreas["Default"] = $oPALChartArea
	
    #// Add each of the Series objects to the chart.
	ForEach ($Series in $htOfSeriesObjects)
	{
		$oPALChart.Series[$Series.Name] = $Series
	}
	
	#// Chart size
	$oChartSize = New-Object System.Drawing.Size
	$oChartSize.Width = $CHART_WIDTH
	$oChartSize.Height = $CHART_HEIGHT
	$oPALChart.Size = $oChartSize
	
	#// Chart Title
	[Void] $oPALChart.Titles.Add($sChartTitle)
	
	#// Chart Legend
	$oLegend = New-Object System.Windows.Forms.DataVisualization.Charting.Legend
	[Void] $oPALChart.Legends.Add($oLegend)

	#// Save the chart image to a PNG file. PNG files are better quality images.
	$oPALChartImageFormat = [System.Windows.Forms.DataVisualization.Charting.ChartImageFormat]"Png"
    $sSaveFilePath
	[Void] $oPALChart.SaveImage($sSaveFilePath, $oPALChartImageFormat)	
}

Function CreatePalCharts
{
    param([System.Collections.ArrayList] $ArrayListOfCounterSeries, [System.Collections.ArrayList] $ArrayListOfThresholdSeries, [System.Int32] $MaxNumberOfItemsInChart = 10, [System.String] $OutputDirectoryPath = '', [System.String] $ImageFileName = '', [System.String] $ChartTitle = '')
    $alOfChartFilesPaths = New-Object System.Collections.ArrayList
    
    If ($ArrayListOfCounterSeries.Count -eq 0)
    {
        Return $alOfChartFilesPaths
    }
        
    [System.Int32] $a = 0
    [System.Int32] $iChartNumber = 0
    [System.String] $sFilePath = ''
    [System.Boolean] $bFileExists = $False
    Do 
    {
        $alNewChartSeries = New-Object System.Collections.ArrayList
        #// Add thresholds
        For ($t=0;$t -lt $ArrayListOfThresholdSeries.Count;$t++)
        {
            $alNewChartSeries += $ArrayListOfThresholdSeries[$t]
        }        
        #// Add counter instances
        If (($ArrayListOfCounterSeries.Count - 1 - $a) -gt $MaxNumberOfItemsInChart)
        {
            $b = 0
            Do
            {
                $alNewChartSeries += $ArrayListOfCounterSeries[$a]
                $a++
                $b++
            } until ($b -ge $MaxNumberOfItemsInChart)
        }
        Else
        {
            Do
            {
                $alNewChartSeries += $ArrayListOfCounterSeries[$a]
                $a++
            } until ($a -ge $ArrayListOfCounterSeries.Count)  
        }

        #// Write chart
        $iChartNumber = 0
        Do
        {
            $sFilePath = $OutputDirectoryPath + $ImageFileName + "$iChartNumber" + '.png'
            $bFileExists = Test-Path -Path $sFilePath
            $iChartNumber++
        } until ($bFileExists -eq $False)
        $sFilePath = GenerateMSChart $ChartTitle $sFilePath $alNewChartSeries
        $alOfChartFilesPaths += $sFilePath        
    } until ($a -ge $ArrayListOfCounterSeries.Count)
    $alOfChartFilesPaths    
}

Function GeneratePalChart
{
	param($XmlChart,$XmlAnalysisInstance)

    $alChartFilePaths = New-Object System.Collections.ArrayList
    $aDateTimes = $aTime
    $htCounterValues = @{}
    $alOfSeries = New-Object System.Collections.ArrayList    
    
    If ($(Test-property -InputObject $XmlChart -Name 'ISTHRESHOLDSADDED') -eq $False)
    {
        SetXmlChartIsThresholdAddedAttribute -XmlChart $XmlChart
    }

    If ($XmlChart.ISTHRESHOLDSADDED -eq "True")
    {		
		#// Already added by the GenerateDataSource function.
		#PrepareChartCodeReplacements -XmlAnalysisInstance $XmlAnalysisInstance
		
        $alOfChartThresholdSeries = New-Object System.Collections.ArrayList

        ForEach ($XmlChartSeries in $XmlChart.SelectNodes("./SERIES"))
        {
            $global:MinSeriesCollection = New-Object System.Collections.ArrayList
            $global:MaxSeriesCollection = New-Object System.Collections.ArrayList
            
            $ExpressionPath = $XmlChartSeries.NAME
            $Name = $XmlChartSeries.NAME

        	ForEach ($XmlCode in $XmlChartSeries.SelectNodes("./CODE"))
        	{
                $sCode = $XmlCode.get_innertext()
                #// Replace all of the variables with their hash table version.
                ForEach ($sKey in $htCodeReplacements.Keys)
                {
                    $sCode = $sCode -Replace $sKey,$htCodeReplacements[$sKey]
                }
                #// Execute the code
                ExecuteCodeForGeneratedDataSource -Code $sCode -Name $Name -ExpressionPath $ExpressionPath -htVariables $htVariables -htQuestionVariables $htQuestionVariables        
                Break #// Only execute one block of code, so breaking out.
        	}
            
        	$oSeriesData = New-Object pscustomobject
        	Add-Member -InputObject $oSeriesData -MemberType NoteProperty -Name Name -Value $XmlChartSeries.NAME
            Add-Member -InputObject $oSeriesData -MemberType NoteProperty -Name MinValues -Value $MinSeriesCollection
            Add-Member -InputObject $oSeriesData -MemberType NoteProperty -Name MaxValues -Value $MaxSeriesCollection
            
            [void] $alOfChartThresholdSeries.Add($oSeriesData)        
        }
    
        $IsWarningThresholds = $False
        $IsCriticalThreshols = $False
        ForEach ($oChartThresholdSeriesInstance in $alOfChartThresholdSeries)
        {
            If ($oChartThresholdSeriesInstance.Name -eq "Warning")
            {
                $IsWarningThresholds = $True
                $MinWarningThresholdValues = $oChartThresholdSeriesInstance.MinValues
                $MaxWarningThresholdValues = $oChartThresholdSeriesInstance.MaxValues
            }
            If ($oChartThresholdSeriesInstance.Name -eq "Critical")
            {
                $IsCriticalThreshols = $True
                $MinCriticalThresholdValues = $oChartThresholdSeriesInstance.MinValues
                $MaxCriticalThresholdValues = $oChartThresholdSeriesInstance.MaxValues
            }
        }
		
        If (($IsCriticalThreshols -eq $True) -and ($IsWarningThresholds -eq $True))
        {
            AddWarningCriticalThresholdRangesToXml -XmlChartInstance $XmlChart -WarningMinValues $MinWarningThresholdValues -WarningMaxValues $MaxWarningThresholdValues -CriticalMinValues $MinCriticalThresholdValues -CriticalMaxValues $MaxCriticalThresholdValues
        }
        Else
        {
            If ($IsCriticalThreshols -eq $True)
            {
                AddWarningCriticalThresholdRangesToXml -XmlChartInstance $XmlChart -CriticalMinValues $MinCriticalThresholdValues -CriticalMaxValues $MaxCriticalThresholdValues
            }
            Else
            {
                AddWarningCriticalThresholdRangesToXml -XmlChartInstance $XmlChart -WarningMinValues $MinWarningThresholdValues -WarningMaxValues $MaxWarningThresholdValues
            }
        }		
		
        #// Populate $htCounterValues
        ForEach ($XmlCounterDataSource in $XmlAnalysisInstance.SelectNodes("./DATASOURCE"))
        {
            If ($XmlChart.DATASOURCE -eq $XmlCounterDataSource.EXPRESSIONPATH)
            {
                ForEach ($XmlDataSourceCounterInstance in $XmlCounterDataSource.SelectNodes("./COUNTERINSTANCE"))
                {
                    If ($(Test-XmlBoolAttribute -InputObject $XmlDataSourceCounterInstance -Name 'ISALLNULL') -eq $True)
                    {
                        $IsAllNull = $True
                    }
                    Else
                    {
                        $IsAllNull = $False
                    }
                    
                    If ($IsAllNull -eq $False)
                    {
                        $aValues = $htCounterInstanceStats[$XmlDataSourceCounterInstance.NAME].Value
                        #// Check if this is a named instance of SQL Server
                        If (($htCounterInstanceStats[$XmlDataSourceCounterInstance.NAME].CounterObject.Contains('MSSQL$') -eq $True) -or ($htCounterInstanceStats[$XmlDataSourceCounterInstance.NAME].CounterObject.Contains('MSOLAP$') -eq $True))
                        {
                            $sSqlNamedInstance = ExtractSqlNamedInstanceFromCounterObjectPath -sCounterObjectPath $htCounterInstanceStats[$XmlDataSourceCounterInstance.NAME].CounterObject
                            If ($XmlDataSourceCounterInstance.COUNTERINSTANCE -eq '')
                            {
        						$CounterLabel = $XmlDataSourceCounterInstance.COUNTERCOMPUTER + "/" + $sSqlNamedInstance
                            }
                            Else
                            {
                                $CounterLabel = $XmlDataSourceCounterInstance.COUNTERCOMPUTER + "/" + $sSqlNamedInstance + "/" + $XmlDataSourceCounterInstance.COUNTERINSTANCE
                            }                            
                        }
                        Else
                        {
                            If ($XmlDataSourceCounterInstance.COUNTERINSTANCE -eq '')
                            {
        						$CounterLabel = $XmlDataSourceCounterInstance.COUNTERCOMPUTER
                            }
                            Else
                            {
                                $CounterLabel = $XmlDataSourceCounterInstance.COUNTERCOMPUTER + "/" + $XmlDataSourceCounterInstance.COUNTERINSTANCE
                            }
                        }
                        [void] $htCounterValues.Add($CounterLabel,$aValues)
                    }
                }
            }
        }
        If ($htCounterValues.Count -gt 0)
        {
            If ($(Test-property -InputObject $XmlChart -Name 'BACKGRADIENTSTYLE') -eq $True)
            {
                If (($IsCriticalThreshols -eq $True) -and ($IsWarningThresholds -eq $True))
                {
                    ConvertCounterArraysToSeriesHashTable $alOfSeries $aDateTimes $htCounterValues $true $MinWarningThresholdValues $MaxWarningThresholdValues $MinCriticalThresholdValues $MaxCriticalThresholdValues $XmlChart.BACKGRADIENTSTYLE
                }
                Else
                {
                    If ($IsCriticalThreshols -eq $True)
                    {
                        ConvertCounterArraysToSeriesHashTable $alOfSeries $aDateTimes $htCounterValues $true $null $null $MinCriticalThresholdValues $MaxCriticalThresholdValues $XmlChart.BACKGRADIENTSTYLE
                    }
                    Else
                    {
                        ConvertCounterArraysToSeriesHashTable $alOfSeries $aDateTimes $htCounterValues $true $MinWarningThresholdValues $MaxWarningThresholdValues $null $null $XmlChart.BACKGRADIENTSTYLE
                    }
                }        
                
            }
            Else
            {
                If (($IsCriticalThreshols -eq $True) -and ($IsWarningThresholds -eq $True))
                {
                	ConvertCounterArraysToSeriesHashTable $alOfSeries $aDateTimes $htCounterValues $true $MinWarningThresholdValues $MaxWarningThresholdValues $MinCriticalThresholdValues $MaxCriticalThresholdValues
                }
                Else
                {
                    If ($IsCriticalThreshols -eq $True)
                    {
                        ConvertCounterArraysToSeriesHashTable $alOfSeries $aDateTimes $htCounterValues $true $null $null $MinCriticalThresholdValues $MaxCriticalThresholdValues
                    }
                    Else
                    {
                        ConvertCounterArraysToSeriesHashTable $alOfSeries $aDateTimes $htCounterValues $true $MinWarningThresholdValues $MaxWarningThresholdValues $null $null
                    }
                }
            }
        }
        Else
        {
            Write-Warning "`t[GeneratePalChart] No data to chart."
        }        
    }
    Else
    {
        #// Populate $htCounterValues
        ForEach ($XmlCounterDataSource in $XmlAnalysisInstance.SelectNodes("./DATASOURCE"))
        {
            If ($XmlChart.DATASOURCE -eq $XmlCounterDataSource.EXPRESSIONPATH)
            {
                ForEach ($XmlDataSourceCounterInstance in $XmlCounterDataSource.SelectNodes("./COUNTERINSTANCE"))
                {
                    $aValues = $htCounterInstanceStats[$XmlDataSourceCounterInstance.NAME].Value
                    #// Check if this is a named instance of SQL Server
                    If (($htCounterInstanceStats[$XmlDataSourceCounterInstance.NAME].CounterObject.Contains('MSSQL$') -eq $True) -or ($htCounterInstanceStats[$XmlDataSourceCounterInstance.NAME].CounterObject.Contains('MSOLAP$') -eq $True))
                    {
                        $sSqlNamedInstance = ExtractSqlNamedInstanceFromCounterObjectPath -sCounterObjectPath $htCounterInstanceStats[$XmlDataSourceCounterInstance.NAME].CounterPath
                        If ($XmlDataSourceCounterInstance.COUNTERINSTANCE -eq '')
                        {
                            $CounterLabel = $XmlDataSourceCounterInstance.COUNTERCOMPUTER + "/" + $sSqlNamedInstance
                        }
                        Else
                        {
                            $CounterLabel = $XmlDataSourceCounterInstance.COUNTERCOMPUTER + "/" + $sSqlNamedInstance + "/" + $XmlDataSourceCounterInstance.COUNTERINSTANCE
                        }
                    }
                    Else
                    {
                        If ($XmlDataSourceCounterInstance.COUNTERINSTANCE -eq '')
                        {
                            $CounterLabel = $XmlDataSourceCounterInstance.COUNTERCOMPUTER
                        }
                        Else
                        {
                            $CounterLabel = $XmlDataSourceCounterInstance.COUNTERCOMPUTER + "/" + $XmlDataSourceCounterInstance.COUNTERINSTANCE
                        }
                    }
                    [void] $htCounterValues.Add($CounterLabel,$aValues)
                }
            }   
        }
        If ($htCounterValues.Count -gt 0)
        {
            ConvertCounterArraysToSeriesHashTable $alOfSeries $aDateTimes $htCounterValues $False
        }
        Else
        {
            Write-Warning "`t[GeneratePalChart] No data to chart."
        }
    }    
    
    #// If there are too many counter instances in a data source for one chart, then need to do multiple charts.
    $ImageFileName = ConvertCounterToFileName -sCounterPath $XmlChart.DATASOURCE
    $OutputDirectoryPath = $htHTMLReport["ResourceDirectoryPath"]	
	$sChartTitle = $XmlChart.CHARTTITLE
	$MaxNumberOfItemsInChart = $CHART_MAX_INSTANCES

    $alThresholdsOfSeries = New-Object System.Collections.ArrayList
    $alNonThresholdsOfSeries = New-Object System.Collections.ArrayList
    For ($t=0;$t -lt $alOfSeries.Count;$t++)
    {
        If (($($alOfSeries[$t].Name.Contains('Warning')) -eq $True) -or ($($alOfSeries[$t].Name.Contains('Critical')) -eq $True))
        {
            $alThresholdsOfSeries += $alOfSeries[$t]
        }
        Else
        {
            $alNonThresholdsOfSeries += $alOfSeries[$t]
        }        
    }
    
    #// Put _Total and _Global_ instances in their own chart series
    $alTotalInstancesSeries = New-Object System.Collections.ArrayList
    $alAllOthersOfSeries = New-Object System.Collections.ArrayList
    For ($t=0;$t -lt $alNonThresholdsOfSeries.Count;$t++)
    {
        If (($alNonThresholdsOfSeries[$t].Name.Contains('_Total') -eq $True) -or ($alNonThresholdsOfSeries[$t].Name.Contains('_Global_') -eq $True))
        {
            $alTotalInstancesSeries += $alNonThresholdsOfSeries[$t]
        }
        Else
        {
            $alAllOthersOfSeries += $alNonThresholdsOfSeries[$t]
        }
    }

    #// Chart all of the _Total instances
    If ($alTotalInstancesSeries.Count -gt 0)
    {
        $alFilesPaths = CreatePalCharts -ArrayListOfCounterSeries $alTotalInstancesSeries -ArrayListOfThresholdSeries $alThresholdsOfSeries -MaxNumberOfItemsInChart $MaxNumberOfItemsInChart -OutputDirectoryPath $OutputDirectoryPath -ImageFileName $ImageFileName -ChartTitle $sChartTitle
        $alFilesPaths | ForEach-Object {[void] $alChartFilePaths.Add($_)}
    }
    
    #// Chart all non-_Total instances
    If ($alAllOthersOfSeries.Count -gt 0)
    {
        $alFilesPaths = CreatePalCharts -ArrayListOfCounterSeries $alAllOthersOfSeries -ArrayListOfThresholdSeries $alThresholdsOfSeries -MaxNumberOfItemsInChart $MaxNumberOfItemsInChart -OutputDirectoryPath $OutputDirectoryPath -ImageFileName $ImageFileName -ChartTitle $sChartTitle
        $alFilesPaths | ForEach-Object {[void] $alChartFilePaths.Add($_)}
    }   
    $alChartFilePaths
}

Function GenerateQuantizedTrendValueArray
{
	param($ArrayOfQuantizedAvgs,$AnalysisIntervalInSeconds,$DataTypeAsString)
    If (($ArrayOfQuantizedAvgs -is [System.Collections.ArrayList]) -or ($ArrayOfQuantizedAvgs -is [System.object[]]))
    {
    	$alQuantizedValues = New-Object System.Collections.ArrayList
    	[void] $alQuantizedValues.Add(0)
    	For ($i = 1; $i -le $ArrayOfQuantizedAvgs.GetUpperBound(0);$i++)
    	{
    		$iTrendValue = CalculateTrend -ArrayOfQuantizedAvgs $ArrayOfQuantizedAvgs[0..$i] -AnalysisIntervalInSeconds $AnalysisInterval -DataTypeAsString "Integer"
    		[void] $alQuantizedValues.Add($iTrendValue)
    	}
    	$alQuantizedValues
    }
    Else
    {
        Return $ArrayOfQuantizedAvgs
    }
}


Function RemoveDashesFromArray
{
    param($Array)
    $Array | Where-Object {$_ -notlike '-'}
}


Function CalculateTrend
{
	param($ArrayOfQuantizedAvgs,$AnalysisIntervalInSeconds,$DataTypeAsString)
    $iSum = 0
    If (($ArrayOfQuantizedAvgs -is [System.Collections.ArrayList]) -or ($ArrayOfQuantizedAvgs -is [System.object[]]))
    {
    	If ($ArrayOfQuantizedAvgs -is [System.object[]])
    	{
    		$alDiff = New-Object System.Collections.ArrayList
    		$iUb = $ArrayOfQuantizedAvgs.GetUpperBound(0)
    		If ($iUb -gt 0)
    		{
    			For ($a = 1;$a -le $iUb;$a++)
    			{
                    $ArrayA = RemoveDashesFromArray -Array $ArrayOfQuantizedAvgs[$a]
                    $ArrayB = RemoveDashesFromArray -Array $ArrayOfQuantizedAvgs[$($a-1)]
                    If (($ArrayA -eq $null) -or ($ArrayB -eq $null))
                    {
                        $iDiff = 0
                    }
                    Else
                    {
    				    $iDiff = $ArrayA - $ArrayB
                    }
    				[void] $alDiff.Add($iDiff)
    			}
    		}
    		Else
    		{
    			Return $ArrayOfQuantizedAvgs[0]
    		}
    		
    		ForEach ($a in $alDiff)
    		{
    			$iSum = $iSum + $a
    		}
    		$iAvg = $iSum / $alDiff.Count
    		CalculateHourlyTrend -Value $iAvg -AnalysisIntervalInSeconds $AnalysisIntervalInSeconds -DataTypeAsString $DataTypeAsString
    	}
    	Else
    	{
    		$ArrayOfQuantizedAvgs
    	}
    }
    Else
    {
        Return $ArrayOfQuantizedAvgs
    }
}


Function GetCounterComputer
{
    param($sCounterPath)
    
	#'\\IDCWEB1\Processor(_Total)\% Processor Time"
	[string] $sComputer = ""
	
	If ($sCounterPath.substring(0,2) -ne "\\")
	{
		Return ""
	}
	$sComputer = $sCounterPath.substring(2)
	$iLocThirdBackSlash = $sComputer.IndexOf("\")
	$sComputer = $sComputer.substring(0,$iLocThirdBackSlash)
	Return $sComputer
}

Function RemoveCounterComputer
{
    param($sCounterPath)
    
	#'\\IDCWEB1\Processor(_Total)\% Processor Time"
	[string] $sString = ""
	#// Remove the double backslash if exists
	If ($sCounterPath.substring(0,2) -eq "\\")
	{		
		$sComputer = $sCounterPath.substring(2)
		$iLocThirdBackSlash = $sComputer.IndexOf("\")
		$sString = $sComputer.substring($iLocThirdBackSlash)
	}
	Else
	{
		$sString = $sCounterPath
	}		
		Return $sString	
}


Function RemoveCounterNameAndComputerName
{
    param($sCounterPath)
    
    If ($sCounterPath.substring(0,2) -eq "\\")
    {
    	$sCounterObject = RemoveCounterComputer $sCounterPath
    }
    Else
    {
        $sCounterObject = $sCounterPath
    }
	# \Paging File(\??\C:\pagefile.sys)\% Usage Peak
	# \(MSSQL|SQLServer).*:Memory Manager\Total Server Memory (KB)
	$aCounterObject = $sCounterObject.split("\")
	$iLenOfCounterName = $aCounterObject[$aCounterObject.GetUpperBound(0)].length
	$sCounterObject = $sCounterObject.substring(0,$sCounterObject.length - $iLenOfCounterName)
	$sCounterObject = $sCounterObject.Trim("\")
    Return $sCounterObject 	    
}



Function GetCounterObject
{
    param($sCounterPath)
	$sCounterObject = RemoveCounterNameAndComputerName $sCounterPath
	#// "Paging File(\??\C:\pagefile.sys)"
    
    If ($sCounterObject -ne '')
    {
    	$Char = $sCounterObject.Substring(0,1)
    	If ($Char -eq "`\")
    	{
    		$sCounterObject = $sCounterObject.SubString(1)
    	}	
    	
    	$Char = $sCounterObject.Substring($sCounterObject.Length-1,1)	
    	If ($Char -ne "`)")
    	{
    		Return $sCounterObject
    	}	
    	$iLocOfCounterInstance = 0
    	$iRightParenCount = 0
    	For ($a=$sCounterObject.Length-1;$a -gt 0;$a = $a - 1)
    	{			
    		$Char = $sCounterObject.Substring($a,1)
    		If ($Char -eq "`)")
    		{
    			$iRightParenCount = $iRightParenCount + 1
    		}
    		If ($Char -eq "`(")
    		{
    			$iRightParenCount = $iRightParenCount - 1
    		}
    		$iLocOfCounterInstance = $a
    		If ($iRightParenCount -eq 0){break}
    	}
	   Return $sCounterObject.Substring(0,$iLocOfCounterInstance)    
    }
    Else
    {
        Return ""
    }
}

Function GetCounterInstance
{
    param($sCounterPath)
    
	$sCounterObject = RemoveCounterNameAndComputerName $sCounterPath	
	#// "Paging File(\??\C:\pagefile.sys)"
	$Char = $sCounterObject.Substring(0,1)	
	If ($Char -eq "`\")
	{
		$sCounterObject = $sCounterObject.SubString(1)
	}
	$Char = $sCounterObject.Substring($sCounterObject.Length-1,1)	
	If ($Char -ne "`)")
	{
		Return ""
	}	
	$iLocOfCounterInstance = 0
	$iRightParenCount = 0
	For ($a=$sCounterObject.Length-1;$a -gt 0;$a = $a - 1)
	{			
		$Char = $sCounterObject.Substring($a,1)
		If ($Char -eq "`)")
		{
			$iRightParenCount = $iRightParenCount + 1
		}
		If ($Char -eq "`(")
		{
			$iRightParenCount = $iRightParenCount - 1
		}
		$iLocOfCounterInstance = $a
		If ($iRightParenCount -eq 0){break}
	}
	$iLenOfInstance = $sCounterObject.Length - $iLocOfCounterInstance - 2
	Return $sCounterObject.Substring($iLocOfCounterInstance+1, $iLenOfInstance)
}

Function GetCounterName
{
    param($sCounterPath)
    
	$aCounterPath = @($sCounterPath.Split("\"))
	Return $aCounterPath[$aCounterPath.GetUpperBound(0)]
}


Function MakeNumeric
{
	param($Values)
	#// Make an array all numeric
    $alNewArray = New-Object System.Collections.ArrayList
    If (($Values -is [System.Collections.ArrayList]) -or ($Values -is [Array]))
    {    	
    	For ($i=0;$i -lt $Values.Count;$i++)
    	{
    		If ($(IsNumeric -Value $Values[$i]) -eq $True)
    		{
    			[Void] $alNewArray.Add([System.Double]$Values[$i])
    		}
    	}    	
    }
    Else
    {
        [Void] $alNewArray.Add([System.Double]$Values)
    }
    $alNewArray
}


Function GenerateDataSourceData($XmlAnalysis, $XmlAnalysisInstance, $XmlGeneratedDataSource)
{
	#// Add a code replacement for the generated data source collection
	$alGeneratedDataSourceCollection = New-Object System.Collections.ArrayList
	[void] $htVariables.Add($XmlGeneratedDataSource.COLLECTIONVARNAME,$alGeneratedDataSourceCollection)
	$sCollectionName = $XmlGeneratedDataSource.COLLECTIONVARNAME
	$sCollectionNameWithBackslash = "\`$$sCollectionName"
	$sCollectionNameWithDoubleQuotes = "`"$sCollectionName`""
	$sCollectionVarName = "`$htVariables[$sCollectionNameWithDoubleQuotes]"
	[void] $htCodeReplacements.Add($sCollectionNameWithBackslash,$sCollectionVarName)
        
    #// Expose the Generated Data Source EXPRESSIONPATH as a variable.
	$ExpressionPath = $XmlGeneratedDataSource.EXPRESSIONPATH
        
    #// Expose the Generated Data Source NAME as a variable.
	$Name = $XmlGeneratedDataSource.NAME
            
	ForEach ($XmlCode in $XmlGeneratedDataSource.SelectNodes("./CODE"))
	{
		$sCode = $XmlCode.get_innertext()
		#'Code before changes:' >> CodeDebug.txt
		#'====================' >> CodeDebug.txt
		#$sCode >> CodeDebug.txt            
		#// Replace all of the variables with their hash table version.
		ForEach ($sKey in $htCodeReplacements.Keys)
		{
			$sCode = $sCode -Replace $sKey,$htCodeReplacements[$sKey]
		}
		#// Execute the code
		ExecuteCodeForGeneratedDataSource -Code $sCode -Name $Name -ExpressionPath $ExpressionPath -htVariables $htVariables -htQuestionVariables $htQuestionVariables        
		Break #// Only execute one block of code, so breaking out.
	}
    $alNewGeneratedCounters = New-Object System.Collections.ArrayList    
   	ForEach ($sKey in $htVariables[$XmlGeneratedDataSource.COLLECTIONVARNAME].Keys)
   	{                    
		$aValue = $htVariables[$XmlGeneratedDataSource.COLLECTIONVARNAME][$sKey]       
		If ($alQuantizedIndex -eq $null)
		{
			$alQuantizedIndex = GenerateQuantizedIndexArray -ArrayOfTimes $aTime -AnalysisIntervalInSeconds $AnalysisInterval
		}
		If ($global:alQuantizedTime -eq $null)
		{
			$global:alQuantizedTime = GenerateQuantizedTimeArray -ArrayOfTimes $aTime -QuantizedIndexArray $alQuantizedIndex
		}       
		
        $MightBeArrayListOrDouble = $(MakeNumeric -Values $aValue)
        $alAllNumeric = New-Object System.Collections.ArrayList
        If (($MightBeArrayListOrDouble -is [System.Collections.ArrayList]) -or ($MightBeArrayListOrDouble -is [Array]))
        {
            [System.Collections.ArrayList] $alAllNumeric = $MightBeArrayListOrDouble
        }
        Else
        {            
            $AlAllNumeric.Add($MightBeArrayListOrDouble)
        }
        
		$alQuantizedAvgValues = GenerateQuantizedAvgValueArray -ArrayOfValues $alAllNumeric -ArrayOfQuantizedIndexes $alQuantizedIndex -DataTypeAsString $($XmlGeneratedDataSource.DATATYPE)
		$alQuantizedMinValues = GenerateQuantizedMinValueArray -ArrayOfValues $alAllNumeric -ArrayOfQuantizedIndexes $alQuantizedIndex -DataTypeAsString $($XmlGeneratedDataSource.DATATYPE)
		$alQuantizedMaxValues = GenerateQuantizedMaxValueArray -ArrayOfValues $alAllNumeric -ArrayOfQuantizedIndexes $alQuantizedIndex -DataTypeAsString $($XmlGeneratedDataSource.DATATYPE)
		$alQuantizedTrendValues = GenerateQuantizedTrendValueArray -ArrayOfQuantizedAvgs $alQuantizedAvgValues -AnalysisIntervalInSeconds $AnalysisInterval -DataTypeAsString "Integer"

		$oStats = $alAllNumeric | Measure-Object -Average -Minimum -Maximum
		$Min = $(ConvertToDataType -ValueAsDouble $oStats.Minimum -DataTypeAsString $XmlGeneratedDataSource.DATATYPE)
		$Avg = $(ConvertToDataType -ValueAsDouble $oStats.Average -DataTypeAsString $XmlGeneratedDataSource.DATATYPE)
		$Max = $(ConvertToDataType -ValueAsDouble $oStats.Maximum -DataTypeAsString $XmlGeneratedDataSource.DATATYPE)
		$Trend = $(ConvertToDataType -ValueAsDouble $alQuantizedTrendValues[$($alQuantizedTrendValues.GetUpperBound(0))] -DataTypeAsString $XmlGeneratedDataSource.DATATYPE)
		$StdDev = $(CalculateStdDev -Values $alAllNumeric)
		$StdDev = $(ConvertToDataType -ValueAsDouble $StdDev -DataTypeAsString $XmlGeneratedDataSource.DATATYPE)
		$PercentileSeventyth = $(CalculatePercentile -Values $alAllNumeric -Percentile 70)
		$PercentileSeventyth = $(ConvertToDataType -ValueAsDouble $PercentileSeventyth -DataTypeAsString $XmlGeneratedDataSource.DATATYPE)
		$PercentileEightyth = $(CalculatePercentile -Values $alAllNumeric -Percentile 80)
		$PercentileEightyth = $(ConvertToDataType -ValueAsDouble $PercentileEightyth -DataTypeAsString $XmlGeneratedDataSource.DATATYPE)
		$PercentileNinetyth = $(CalculatePercentile -Values $alAllNumeric -Percentile 90)
		$PercentileNinetyth = $(ConvertToDataType -ValueAsDouble $PercentileNinetyth -DataTypeAsString $XmlGeneratedDataSource.DATATYPE)            
	
		$sCounterPath = $sKey
		$sCounterComputer = GetCounterComputer -sCounterPath $sCounterPath
		$sCounterObject = GetCounterObject -sCounterPath $sCounterPath
		$sCounterName = GetCounterName -sCounterPath $sCounterPath
		$sCounterInstance = GetCounterInstance -sCounterPath $sCounterPath
       
		AddToCounterInstanceStatsArrayList $sKey $aTime $aValue $alQuantizedTime $alQuantizedMinValues $alQuantizedAvgValues $alQuantizedMaxValues $alQuantizedTrendValues $sCounterComputer $sCounterObject $sCounterName $sCounterInstance $Min $Avg $Max $Trend $StdDev $PercentileSeventyth $PercentileEightyth $PercentileNinetyth
           
		$XmlNewCounterInstance = $XmlAnalysis.CreateElement("COUNTERINSTANCE")
		$XmlNewCounterInstance.SetAttribute("NAME", $sCounterPath)
		$XmlNewCounterInstance.SetAttribute("MIN", $([string]::Join(',',$Min)))
		$XmlNewCounterInstance.SetAttribute("AVG", $([string]::Join(',',$Avg)))
		$XmlNewCounterInstance.SetAttribute("MAX", $([string]::Join(',',$Max)))
		$XmlNewCounterInstance.SetAttribute("TREND", $([string]::Join(',',$Trend)))
		$XmlNewCounterInstance.SetAttribute("STDDEV", $([string]::Join(',',$StdDev)))
		$XmlNewCounterInstance.SetAttribute("PERCENTILESEVENTYTH", $([string]::Join(',',$PercentileSeventyth)))
		$XmlNewCounterInstance.SetAttribute("PERCENTILEEIGHTYTH", $([string]::Join(',',$PercentileEightyth)))
		$XmlNewCounterInstance.SetAttribute("PERCENTILENINETYTH", $([string]::Join(',',$PercentileNinetyth)))            
		$XmlNewCounterInstance.SetAttribute("QUANTIZEDMIN", $([string]::Join(',',$alQuantizedMinValues)))       
		$XmlNewCounterInstance.SetAttribute("QUANTIZEDAVG", $([string]::Join(',',$alQuantizedAvgValues)))
		$XmlNewCounterInstance.SetAttribute("QUANTIZEDMAX", $([string]::Join(',',$alQuantizedMaxValues)))
		$XmlNewCounterInstance.SetAttribute("QUANTIZEDTREND", $([string]::Join(',',$alQuantizedTrendValues)))
		$XmlNewCounterInstance.SetAttribute("COUNTERPATH", $sCounterPath)
		$XmlNewCounterInstance.SetAttribute("COUNTERCOMPUTER", $sCounterComputer)
		$XmlNewCounterInstance.SetAttribute("COUNTEROBJECT", $sCounterObject)
		$XmlNewCounterInstance.SetAttribute("COUNTERNAME", $sCounterName)
		$XmlNewCounterInstance.SetAttribute("COUNTERINSTANCE", $sCounterInstance)
		[void] $XmlGeneratedDataSource.AppendChild($XmlNewCounterInstance)
        [void] $alNewGeneratedCounters.Add($htCounterInstanceStats[$sKey])      
   }
   #// Replace the collection made from the generation code so that it is the same as other counters.
   $htVariables[$XmlGeneratedDataSource.COLLECTIONVARNAME] = $alNewGeneratedCounters
}


				
Function PrepareGeneratedCodeReplacements
{
    param($XmlAnalysisInstance)
    	
    #// Generated data source, charts, and thresholds assume that all of the counterlog counters are available to it.
	ForEach ($XmlCounterDataSource in $XmlAnalysisInstance.SelectNodes('./DATASOURCE'))
	{       
		If ($XmlCounterDataSource.TYPE -eq "CounterLog")
		{
			$global:alCounterDataSourceCollection = New-Object System.Collections.ArrayList
            ForEach ($XmlCounterDataSourceInstance in $XmlCounterDataSource.SelectNodes("./COUNTERINSTANCE"))
            {
                If ($(Test-XmlBoolAttribute -InputObject $XmlCounterDataSourceInstance -Name 'ISALLNULL') -eq $True)
                {
                    $IsAllNull = $True
                }
                Else
                {
                    $IsAllNull = $False
                }
                
                If ($IsAllNull -eq $False)
                {
                    [void] $alCounterDataSourceCollection.Add($htCounterInstanceStats[$XmlCounterDataSourceInstance.NAME])
                }
            }
            [void] $htVariables.Add($XmlCounterDataSource.COLLECTIONVARNAME,$alCounterDataSourceCollection)
            $sCollectionName = $XmlCounterDataSource.COLLECTIONVARNAME
            $sCollectionNameWithBackslash = "\`$$sCollectionName"
            $sCollectionNameWithDoubleQuotes = "`"$sCollectionName`""
            $sCollectionVarName = "`$htVariables[$sCollectionNameWithDoubleQuotes]"
            [void] $htCodeReplacements.Add($sCollectionNameWithBackslash,$sCollectionVarName)
		}
	}
                    
    #// Add the code replacements for the question variables
    ForEach ($sKey in $htQuestionVariables.Keys)
    {
        $sModifiedKey = "\`$$sKey"
        $sKeyWithDoubleQuotes = "`"$sKey`""
        $sModifiedVarName = "`$htQuestionVariables[$sKeyWithDoubleQuotes]"
        $IsInHashTable = $htCodeReplacements.Contains($sModifiedKey)
        If ($IsInHashTable -eq $false)
        {            
            [void] $htCodeReplacements.Add($sModifiedKey,$sModifiedVarName)
        }
    }
}
				

Function ConvertTextTrueFalse($str)
{
	If ($str -eq $null)
	{Return $False}
    If ($str -is [System.String])
    {
        $strLower = $str.ToLower()
        If ($strLower -eq 'true')
        {
            Return $True
        }
    	Else 
        {
            Return $False
        }
    }
    Else
    {
        If ($str -is [System.Boolean])
        {
            Return $str
        }
        Else
        {
            Return $False
        }
    }
}
				
				
Function Test-XmlBoolAttribute
{
	param ([Parameter(Position=0,Mandatory=1)]$InputObject,[Parameter(Position=1,Mandatory=1)]$Name)
    
	If ($(Test-property -InputObject $InputObject -Name $Name) -eq $True)
    {
    	If ($(ConvertTextTrueFalse $InputObject.$Name) -eq $True)
        {
        	$True        
       	}
        Else
        {
        	$False
        }
    }
    Else
    {
    	$False
    }
}

Function Test-Property 
{
	#// Function provided by Jeffrey Snover
    #// Tests if a property is a memory of an object.
	param ([Parameter(Position=0,Mandatory=1)]$InputObject,[Parameter(Position=1,Mandatory=1)]$Name)
	[Bool](Get-Member -InputObject $InputObject -Name $Name -MemberType *Property)
}
			

Function DisableAnalysisIfNoCounterInstancesFound($XmlAnalysisInstance)
{
	$XmlAnalysisInstance.SetAttribute("AllCountersFound",'True')
    ForEach ($XmlDataSource in $XmlAnalysisInstance.SelectNodes('./DATASOURCE'))
    {
    	If ($XmlDataSource.TYPE.ToLower() -ne 'generated')
        {
        	$IsAtLeastOneCounterInstanceInDataSource = $False
            :CounterInstanceLoop ForEach ($XmlDataSource in $XmlDataSource.SelectNodes('./COUNTERINSTANCE'))
            {
            	$IsAtLeastOneCounterInstanceInDataSource = $True
               	Break CounterInstanceLoop
            }			
            If ($IsAtLeastOneCounterInstanceInDataSource -eq $False) {$XmlAnalysisInstance.SetAttribute("AllCountersFound",'False')}	
        }
    }
}

Function GetCounterListFromCsvAsText
{
    param($CsvFilePath)
	$oCSVFile = Get-Content $CsvFilePath
    #// Some counters have commas in their instance names, so doing a split with more characters to make it more reliable.
    If ($oCSVFile[0] -is [System.Char])
    {
        Write-Error "[GetCounterListFromCsvAsText]: No usable data found in the log."
        Break Main
    }
    $aRawCounterList = $oCSVFile[0].Trim('"') -split '","'
    $u = $aRawCounterList.GetUpperBound(0)
	$aCounterList = $aRawCounterList[1..$u]
	Return $aCounterList
}


Function GetCounterInstancesAndGenerateCounterStats($XmlDoc,$XmlDataSource)
{	
    #Write-Host 'Get-CounterInstances' $XmlDataSource.EXPRESSIONPATH
    $sDsCounterObject = GetCounterObject -sCounterPath $XmlDataSource.EXPRESSIONPATH
    $sDsCounterName = GetCounterName -sCounterPath $XmlDataSource.EXPRESSIONPATH
    $sDsCounterInstance = GetCounterInstance -sCounterPath $XmlDataSource.EXPRESSIONPATH
	$iCounterIndexInCsv = 0
    If ($global:aCounterLogCounterList -eq "")
    { 
       	$global:aCounterLogCounterList = GetCounterListFromCsvAsText $global:sPerfLogFilePath
    }
    
    If ($(Test-XmlBoolAttribute -InputObject $XmlDataSource -Name 'ISCOUNTEROBJECTREGULAREXPRESSION') -eq $True)
    {
        $IsCounterObjectRegularExpression = $True
    }
    Else
    {
        $IsCounterObjectRegularExpression = $False
    }

    If ($(Test-XmlBoolAttribute -InputObject $XmlDataSource -Name 'ISCOUNTERNAMEREGULAREXPRESSION') -eq $True)
    {
        $IsCounterNameRegularExpression = $True
    }
    Else
    {
        $IsCounterNameRegularExpression = $False
    } 
    
    If ($(Test-XmlBoolAttribute -InputObject $XmlDataSource -Name 'ISCOUNTERINSTANCEREGULAREXPRESSION') -eq $True)
    {
        $IsCounterInstanceRegularExpression = $True
    }
    Else
    {
        $IsCounterInstanceRegularExpression = $False
    }         
    
    :CounterComputerLoop ForEach ($XmlCounterComputerNode in $global:XmlCounterLogCounterInstanceList.SelectNodes('//COUNTERCOMPUTER'))
    {
        :CounterObjectLoop ForEach ($XmlCounterObjectNode in $XmlCounterComputerNode.ChildNodes)
        {
            $IsCounterObjectMatch = $False
            If ($IsCounterObjectRegularExpression -eq $True)
            {
                $sDsCounterObject = GetCounterObject -sCounterPath $XmlDataSource.REGULAREXPRESSIONCOUNTERPATH
                If ($XmlCounterObjectNode.NAME -match $sDsCounterObject)
                {
                    $IsCounterObjectMatch = $True
                }
            }
            Else
            {
                If ($XmlCounterObjectNode.NAME -eq $sDsCounterObject)
                {
                    $IsCounterObjectMatch = $True
                }
            }
            If ($IsCounterObjectMatch -eq $True)
            {
                :CounterNameLoop ForEach ($XmlCounterNameNode in $XmlCounterObjectNode.ChildNodes)
                {
                    $IsCounterNameMatch = $False
                    If ($IsCounterNameRegularExpression -eq $True)
                    {
                        $sDsCounterName = GetCounterName -sCounterPath $XmlDataSource.REGULAREXPRESSIONCOUNTERPATH
                        If ($XmlCounterNameNode.NAME -match $sDsCounterName)
                        {
                            $IsCounterNameMatch = $True
                        }
                    }
                    Else
                    {
                        If ($XmlCounterNameNode.NAME -eq $sDsCounterName)
                        {
                            $IsCounterNameMatch = $True
                        }
                    }
                    If ($IsCounterNameMatch -eq $True)
                    {
                        :CounterInstanceLoop ForEach ($XmlCounterInstanceNode in $XmlCounterNameNode.ChildNodes)
                        {
                            $IsCounterInstanceMatch = $False
                            If (($sDsCounterInstance -eq '') -OR ($sDsCounterInstance -eq '*'))
                            {
                                $IsCounterInstanceMatch = $True                                
                            }
                            Else
                            {
                                If ($IsCounterInstanceRegularExpression -eq $True)
                                {
                                    If ($XmlCounterInstanceNode.NAME -match $sDsCounterInstance)
                                    {
                                        $IsCounterInstanceMatch = $True
                                    }
                                }
                                Else
                                {
                                    If ($sDsCounterInstance -eq $XmlCounterInstanceNode.NAME)
                                    {
                                        $IsCounterInstanceMatch = $True
                                    }
                                }
                            
                            }
                            If ($IsCounterInstanceMatch -eq $True)
                            {
                                ForEach ($XmlExcludeNode in $XmlDataSource.SelectNodes('./EXCLUDE'))
                                {
                                    If ($XmlExcludeNode.INSTANCE -eq $XmlCounterInstanceNode.NAME)
                                    {
                                        $IsCounterInstanceMatch = $False
                                    }
                                }
                            }                            
                            If ($IsCounterInstanceMatch -eq $True)
                            {
                                $iCounterIndexInCsv = [System.Int32]$XmlCounterInstanceNode.COUNTERLISTINDEX
                                 #// Add counter instances to XML node.
                                AddCounterInstancesToXmlDataSource $XmlDoc $XmlDataSource $XmlCounterInstanceNode.COUNTERPATH $XmlCounterComputerNode.NAME $XmlCounterObjectNode.NAME $XmlCounterNameNode.NAME $XmlCounterInstanceNode.NAME $iCounterIndexInCsv
                            }
                        }
                        #break CounterObjectLoop
                    }
                }
            }
        }        
    }
}
	
	
	
Function GetDataSourceData($XmlDoc, $XmlAnalysisInstance, $XmlDataSource)
{
	GetCounterInstancesAndGenerateCounterStats $XmlDoc $XmlDataSource
}


Function ConvertToRelativeFilePaths
{
    param($RootPath,$TargetPath)
    $Result = $TargetPath.Replace($RootPath,'')
    $Result
}

Function Get-LocalizedDecimalSeparator()
{
	Return (get-culture).numberformat.NumberDecimalSeparator
}

$global:htScript["LocalizedThousandsSeparator"] = Get-LocalizedThousandsSeparator
$global:htScript["LocalizedDecimal"] = Get-LocalizedDecimalSeparator

#// Gather data from counter data sources first since the generated data sources will depend on this.
#// Do not process the analysis if it is not enabled.
If ($(Test-XmlBoolAttribute -InputObject $XmlAnalysisInstance -Name 'ENABLED') -eq $True)
{
	$IsEnabled = $True
}
Else
{
	$IsEnabled = $False
}
        
If ($IsEnabled -eq $True)
{
    ForEach ($XmlDataSource in $XmlAnalysisInstance.SelectNodes('./DATASOURCE')) 
    {
        If ($XmlDataSource.TYPE -ne "Generated")
        {
            GetDataSourceData $XmlAnalysis $XmlAnalysisInstance $XmlDataSource
        }
    }
    DisableAnalysisIfNoCounterInstancesFound $XmlAnalysisInstance
    If ($(Test-XmlBoolAttribute -InputObject $XmlAnalysisInstance -Name 'AllCountersFound') -eq $True)
    {
    	$IsAllCountersFound = $True
    }
    Else
    {
    	$IsAllCountersFound = $False
    }
			
	#// Add the counter instances to hash table for use by the generated data source.
	$global:htVariables = @{}
	$global:htCodeReplacements = @{}
	$global:alCounterDataSourceCollection = New-Object System.Collections.ArrayList
    If ($(Test-XmlBoolAttribute -InputObject $XmlAnalysisInstance -Name 'FROMALLCOUNTERSTATS') -eq $True)
    {
    	$IsFromAllCounterStats = $True
    }
    Else
    {
    	$IsFromAllCounterStats = $False
    }

    if ($IsAllCountersFound -eq $True)
    {
		#// If this analysis is generated from the AllCounterStats feature, then don't process it.
		if ($IsFromAllCounterStats -eq $True)
		{
        	ForEach ($XmlCounterDataSource in $XmlAnalysisInstance.SelectNodes('./DATASOURCE'))
            {       
            	If ($XmlCounterDataSource.TYPE -eq "CounterLog")
                {
                	$global:alCounterDataSourceCollection = New-Object System.Collections.ArrayList
                    ForEach ($XmlCounterDataSourceInstance in $XmlCounterDataSource.SelectNodes("./COUNTERINSTANCE"))
                    {
                    	If ($(Test-XmlBoolAttribute -InputObject $XmlCounterDataSourceInstance -Name 'ISALLNULL') -eq $True)
                        {
                        	$IsAllNull = $True
                        }
                        Else
                        {
                        	$IsAllNull = $False
                        }
                                
                        If ($IsAllNull -eq $False)
                        {
                        	[void] $alCounterDataSourceCollection.Add($htCounterInstanceStats[$XmlCounterDataSourceInstance.NAME])
                        }
               		}
                    [void] $htVariables.Add($XmlCounterDataSource.COLLECTIONVARNAME,$alCounterDataSourceCollection)
               	}
     		}                
		}
		Else
		{
			#// Add the counter log data into memory for the processing of generated counters.
			PrepareGeneratedCodeReplacements -XmlAnalysisInstance $XmlAnalysisInstance
		}
	}
            			
    If ($IsAllCountersFound -eq $True)
    {
		#// If this analysis is generated from the AllCounterStats feature, then don't process it.
		if ($IsFromAllCounterStats -eq $True)
		{
			#Do Nothing
		}
		Else
		{
        	#//////////////////////
			#// Generate data sources.
            #//////////////////////
			forEach ($XmlDataSource in $XmlAnalysisInstance.SelectNodes('./DATASOURCE'))
			{
				If ($XmlDataSource.TYPE.ToLower() -eq "generated")
				{
					If ($alCounterExpressionProcessedHistory.Contains($XmlDataSource.NAME) -eq $False)
					{
						GenerateDataSourceData $XmlAnalysis $XmlAnalysisInstance $XmlDataSource
						#Write-Host "." -NoNewline
						[Void] $alCounterExpressionProcessedHistory.Add($XmlDataSource.NAME)
					}
				}
			}
		}
	}

    If ($IsAllCountersFound -eq $True)
    {
    	#//////////////////////
        #// Generate charts.
        #//////////////////////
        $alOfChartFilePaths = New-Object System.Collections.ArrayList
        $alTempFilePaths = New-Object System.Collections.ArrayList
        forEach ($XmlChart in $XmlAnalysisInstance.SelectNodes("./CHART"))
        {			
        	$alTempFilePaths = GeneratePalChart -XmlChart $XmlChart -XmlAnalysisInstance $XmlAnalysisInstance
            [System.Object[]] $alTempFilePaths = @($alTempFilePaths | Where-Object {$_ -ne $null})
            For ($i=0;$i -lt $alTempFilePaths.Count;$i++)
            {
            	$alTempFilePaths[$i] = ConvertToRelativeFilePaths -RootPath $global:htHtmlReport["OutputDirectoryPath"] -TargetPath $alTempFilePaths[$i]
            }
                    
            If ($alTempFilePaths -ne $null) #// Added by Andy from Codeplex.com
            {
            	$result = [string]::Join(',',$alTempFilePaths)
                $XmlChart.SetAttribute("FILEPATHS", $result)
            }
  		}
                
        #//////////////////////
        #// Processing Thresholds
        #//////////////////////                
        PrepareEnvironmentForThresholdProcessing -CurrentAnalysisInstance $XmlAnalysisInstance
        ForEach ($XmlThreshold in $XmlAnalysisInstance.SelectNodes("./THRESHOLD"))
        {
        	ProcessThreshold -XmlAnalysisInstance $XmlAnalysisInstance -XmlThreshold $XmlThreshold
        }
        
    }
}

$XmlAnalysis.PAL.ANALYSIS[$XmlAnalysisInstanceIndex] = $xmlAnalysisInstance

[xml]$XmlAnalysis
