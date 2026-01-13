# Runtime dependencies for ReScenePS
# These are the modules needed for the module to run
@{
    PSDependOptions = @{
        Target     = 'CurrentUser'
        Parameters = @{
            Repository = 'PSGallery'
        }
    }
    'SrrDBAutomationToolkit' = @{
        Version = '0.4.0'
    }
}
