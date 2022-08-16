BEGIN TRY
	PRINT '1'
END TRY
BEGIN CATCH
	DECLARE @PRINT_or_RAISERROR BIT = 1			-- 1 for print 2 for RAISERROR
	DECLARE @ErrMsg NVARCHAR(500) = ERROR_MESSAGE()
	DECLARE @ErrLine NVARCHAR(500) = ERROR_LINE()
	DECLARE @ErrNo nvarchar(6) = CONVERT(NVARCHAR(6),ERROR_NUMBER())
	DECLARE @ErrState nvarchar(2) = CONVERT(NVARCHAR(2),ERROR_STATE())
	DECLARE @ErrSeverity nvarchar(2) = CONVERT(NVARCHAR(2),ERROR_SEVERITY())
	DECLARE @UDErrMsg nvarchar(MAX) = 'Something went wrong during the operation. Depending on your preference the operation will fail or continue, skipping this iteration. System error message:'+CHAR(10)
			+ 'Msg '+@ErrSeverity+', Level '+@ErrSeverity+', State '+@ErrState+', Line '++@ErrLine + CHAR(10)
			+ @ErrMsg
	IF @PRINT_or_RAISERROR = 1
		PRINT @UDErrMsg
	ELSE
		RAISERROR(@UDErrMsg,16,1)
	
END CATCH