# Runtime dependencies for ReScenePS
# These are the modules needed for the module to run
@{
    PSDependOptions = @{
        Target     = 'CurrentUser'
        Parameters = @{
            Repository = 'PSGallery'
        }
    }
    'CRC'           = @{
        Version = '0.0.2'
    }
}
