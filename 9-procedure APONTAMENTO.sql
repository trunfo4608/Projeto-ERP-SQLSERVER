--PROCEDURE PRODUCAO
--GERA MOVIMENTA DE ENTRADA ESTOQUE DO PRODUTO APONTADO
--GERA MOVIMENTO DE SAIDA ESTOQUE DOS PRODUTOS CONSUMIDOS CONFORME FICHA TECNICA
--ALIMENTA TABELA CONSUMO PARA RASTREABILIDADE
--ALIMENTA TABELA APONTAMENTO PARA RASTREABILIDADE
--ATUALIZA TABELAS ORDEM_PROD QTD_PROD E SITUACAO=F FINALIZADO , QUANDO QTD_PLAN=QTD_PROD
--PARAMETROS, COD_EMPRESA,ID_ORDEM,COD_MAT_PROD,QTD_APONT, LOTE
--CONSISTENCIAS DE ESTOQUE
--ORDEM_PROD SITUACAO=A NAO GEROU PEDIDO DE COMPRAS
--ORDEM_PROD SITUACAO=P GEROU PEDIDO DE COMPRAS
--ORDEM_PROD SITUACAO=F FINALIZADA
--FASE 8 INTEGRACAO APONTAMENTOS PRODUCAO ESTOQUE
--EXEC PROC_APONTAMENTO 1,1,10,TESTE1
--DROP PROCEDURE PROC_APONTAMENTO
USE ERP;

CREATE PROCEDURE PROC_APONTAMENTO (@COD_EMPRESA INT,
                                   @ID_ORDEM INT,
								   @COD_MAT_PROD INT,
                                   @QTD_APON DECIMAL(10,2),
								   @LOTE_PROD VARCHAR(20))
	AS 
    BEGIN 
DECLARE @APONTAMENTO TABLE
(
    ID_APON  INT
)
DECLARE 
       
		@QTD_PLAN DECIMAL(10,2),
		@QTD_PROD DECIMAL(10,2),
		@SALDO DECIMAL(10,2),
		@SALDO_AUX DECIMAL(10,2),
		@SITUACAO VARCHAR(1),
		@ERRO_INTERNO INT,
		@DATA_MOVTO DATE,
		@ID_APON INT,
		@COD_MAT_NECES INT,
		@QTD_ATEND DECIMAL(10,2),
		@QTD_LOTE DECIMAL(10,2),
		@TESTE INT,
		@COD_MAT_AUX INT,
		@QTD_NECES_CONS DECIMAL(10,2),
		@LOTE VARCHAR(20),
		@QTD_NECES DECIMAL(10,2)

SET @DATA_MOVTO=GETDATE()

BEGIN TRANSACTION
--PRIMEIRA ETAPA APONTAMENTO ATUALIZA ORDEM E MOVIMENTA ESTOQUE
--PRIMEIRO IF CHECK DE EXISTE ORDEM PARA SELECAO
IF  (SELECT COUNT(*) FROM ORDEM_PROD A
	WHERE COD_EMPRESA=@COD_EMPRESA 
	AND A.COD_MAT_PROD=@COD_MAT_PROD
	AND A.ID_ORDEM=@ID_ORDEM
	AND A.SITUACAO='P') =0 --APENAS ORDEM PLANEJADAS
	BEGIN 
	 SET @ERRO_INTERNO=1
		PRINT 'ERRO1'
	END
--VERIFANDO QTD APONTADA > SALDO PARA NAO PERMITIR APONTAMENTO
ELSE IF (SELECT A.QTD_PLAN-A.QTD_PROD FROM ORDEM_PROD A
	    WHERE COD_EMPRESA=@COD_EMPRESA AND A.ID_ORDEM=@ID_ORDEM)<@QTD_APON
		BEGIN
		  SET @ERRO_INTERNO=2
		  PRINT 'ERRO2'
		END
--VERIFANDO SE MATERIAIS NECESSARIOS TEM SALDO PARA CONSUMO
ELSE IF (SELECT COUNT(*)
	--SELECT B.COD_MAT_NECES,B.QTD_NECES*@QTD_APON NECESSIDADE, C.QTD_SALDO
	 FROM ORDEM_PROD A
	INNER JOIN FICHA_TECNICA B
	ON  A.COD_EMPRESA=B.COD_EMPRESA
	AND A.COD_MAT_PROD=B.COD_MAT_PROD
	INNER JOIN  ESTOQUE C
	ON A.COD_EMPRESA=C.COD_EMPRESA
	AND B.COD_MAT_NECES=C.COD_MAT
	WHERE A.COD_EMPRESA=@COD_EMPRESA
	AND A.ID_ORDEM=@ID_ORDEM
	AND (B.QTD_NECES*@QTD_APON)>C.QTD_SALDO)>0
	BEGIN 
	 SET @ERRO_INTERNO=3
	  PRINT 'ERRO3'
	END
	ELSE
	BEGIN

	BEGIN TRY
	--DECLARANDO CURSO DE APONTAMENTO
	DECLARE APONT CURSOR FOR
	--SELECIONANDO VALORES
	SELECT A.ID_ORDEM,A.COD_MAT_PROD,A.QTD_PLAN,A.QTD_PROD
	FROM ORDEM_PROD A
	WHERE A.COD_EMPRESA=@COD_EMPRESA
	AND A.COD_MAT_PROD=@COD_MAT_PROD
	AND ID_ORDEM=@ID_ORDEM
	AND A.SITUACAO='P' --APENAS ORDEM PLANEJADAS
--ABRINDO CURSOR APONT
OPEN APONT
--LENDO REGISTRO
 FETCH NEXT FROM APONT
 --INSERINDO VALORES NAS VARIAVEIS
 INTO @ID_ORDEM,@COD_MAT_PROD,@QTD_PLAN,@QTD_PROD
 WHILE @@FETCH_STATUS = 0
	BEGIN
	--APENAS APRESENTANDO INFORMA��ES
	SELECT @ID_ORDEM ID_ORDEM,@COD_MAT_PROD COD_MAT_PROD,@QTD_PLAN QTD_PLAN,@QTD_PROD QTD_PROD,
	@QTD_PLAN-@QTD_PROD SALDO		
	SELECT 'QTD APONTADA ',@QTD_APON;
	SELECT 'SALDO ORDEM ',@QTD_PLAN-(@QTD_PROD+@QTD_APON);
	--ATRIBUINDO VALORES
	SET @SALDO=@QTD_PLAN-@QTD_PROD
	SET @SALDO_AUX=@SALDO	
	
	    --INSERT NA TABELA APONTAMENTOS PARA RASTREABILIDADE
		INSERT INTO APONTAMENTOS 
		OUTPUT INSERTED.ID_APON INTO @APONTAMENTO
		VALUES (@COD_EMPRESA,@ID_ORDEM,@COD_MAT_PROD,@QTD_APON,GETDATE(), SYSTEM_USER,@LOTE_PROD)
		--ATRIBUI ID_APON
		SELECT @ID_APON=ID_APON FROM @APONTAMENTO
		--EXECUTA PROC GERA ESTOQUE
		EXEC PROC_GERA_ESTOQUE @COD_EMPRESA,'E',@COD_MAT_PROD,@LOTE_PROD,@QTD_APON,@DATA_MOVTO
		--UPDATE SALDO DA ORDEM
		UPDATE ORDEM_PROD SET QTD_PROD=@QTD_PROD+@QTD_APON
		WHERE COD_EMPRESA=@COD_EMPRESA
			  AND ID_ORDEM=@ID_ORDEM
		      AND COD_MAT_PROD=@COD_MAT_PROD
		SELECT 'ORDEM ATUALIZADA' 
		SET @SALDO=@QTD_PLAN-(@QTD_PROD+@QTD_APON);
		SET @SALDO_AUX=@SALDO
	--END
	
	FETCH NEXT FROM APONT
    INTO @ID_ORDEM,@COD_MAT_PROD,@QTD_PLAN,@QTD_PROD
	
	END 
    CLOSE APONT
	DEALLOCATE APONT
	END TRY --END TRY
    BEGIN CATCH
        SET @ERRO_INTERNO =5;
        print ''
        print 'Erro ocorreu!'
        print 'Mensagem: ' + ERROR_MESSAGE()
        print 'Procedure: ' + ERROR_PROCEDURE()
END CATCH

--INICIO DO SEGUNDO BLOCO CONSUMINDO NECESSIDADES E MOVIMENTANDO ESTOQUE	

BEGIN TRY
--ZERANDO VARIAVEIS

	--DECLARANDO CURSOR NECESSIDADES
	DECLARE NECESSIDADES CURSOR FOR
	--SELECIONANDO VALORES
	SELECT A.ID_ORDEM,A.SITUACAO,A.COD_MAT_PROD,
	A.QTD_PLAN,B.COD_MAT_NECES,B.QTD_NECES,
	@QTD_APON QTD_APON,
	@QTD_APON*B.QTD_NECES QTD_NECES_CONS
	FROM ORDEM_PROD A
	INNER JOIN FICHA_TECNICA B
	ON A.COD_EMPRESA=B.COD_EMPRESA
	AND A.COD_MAT_PROD=B.COD_MAT_PROD
	WHERE A.SITUACAO='P'
	AND A.COD_EMPRESA=@COD_EMPRESA
	AND A.ID_ORDEM=@ID_ORDEM
	AND A.COD_MAT_PROD=@COD_MAT_PROD
	--ABRINDO CURSOR NECESSIDADES
	OPEN NECESSIDADES
	--LENDO VALORES
	FETCH NEXT FROM NECESSIDADES
	--ATRIBUINDO VALORES
	INTO @ID_ORDEM,@SITUACAO,@COD_MAT_PROD,
	     @QTD_PLAN,@COD_MAT_NECES,@QTD_NECES,
	     @QTD_APON,@QTD_NECES_CONS
    
	--ESTUTRUTURA WHILE
    WHILE @@FETCH_STATUS = 0
	BEGIN 
	--APRESENTANDO VALORES
	SELECT @ID_ORDEM ID_ORDEM,@SITUACAO SITUACAO ,@COD_MAT_PROD COD_MAT_PROD,
	      @QTD_PLAN QTD_PLAN,@COD_MAT_NECES COD_MAT_NECES,@QTD_NECES QTD_NECES,
	       @QTD_APON QTD_APON,@QTD_NECES_CONS QTD_NECES_CONS

	--DECLARANDO CURSOR PARA ALIMENTAR CONSUMO E MOVIMENTAR ESTOQUE
	DECLARE ESTOQUE_CONSUMO CURSOR FOR
	SELECT C.COD_MAT,C.QTD_LOTE,C.LOTE,@QTD_NECES_CONS
		FROM  ESTOQUE_LOTE C
		WHERE C.COD_EMPRESA=@COD_EMPRESA 
		AND C.COD_MAT=@COD_MAT_NECES
		AND C.QTD_LOTE>0
	ORDER BY C.COD_MAT,C.LOTE
	--ABRINDO CURSOR
	OPEN ESTOQUE_CONSUMO
	--LENDO REGISTROS DO CURSOR
	FETCH NEXT FROM ESTOQUE_CONSUMO
	--ATRIBUINDO VALORES
	INTO @COD_MAT_NECES,@QTD_LOTE,@LOTE,@QTD_NECES_CONS
	--ATRIBUINDO VALORES A VARIAVEIS
	SET  @SALDO=@QTD_NECES_CONS;
	SET  @SALDO_AUX=@SALDO
	--APRESENTANDO VALORES
	--SELECT @SALDO SALDO,@SALDO_AUX SD_AUX
	--ESTRUTURA WHILE
	WHILE @@FETCH_STATUS = 0
		BEGIN 

	--TESTES
	--VERIFICA�OES DE TROCA DE MATERIAL
			  IF @COD_MAT_AUX<>@COD_MAT_NECES 
			  BEGIN 
				SET @QTD_ATEND=0
			  END
--VERIFICACOES DE SALDO	 <= 0	 
			  IF @SALDO<=0
			  BEGIN 
			  SET @QTD_ATEND=0
			  END
--VERIFICANDO SE SALDO_AUX MAIOR IGUAL A QTD_LOTE
			  IF  @SALDO_AUX>=@QTD_LOTE
			  BEGIN 
			  --ATRIBUINDO VALORES
			      SET  @QTD_ATEND=@QTD_LOTE
				  SET  @SALDO=@SALDO-@QTD_NECES_CONS
				  SET  @SALDO_AUX=@SALDO_AUX-@QTD_LOTE
				  SET  @TESTE='1'	  
			  END
--VERIFICANDO SE SALDO_AUX MENOR A QTD_LOTE
			  ELSE IF  @SALDO_AUX<@QTD_LOTE
			  BEGIN 
			  --ATRIBUINDO VALORES
				  SET  @SALDO=@QTD_NECES_CONS
				  SET  @QTD_ATEND=@SALDO_AUX
				  SET  @SALDO_AUX=@SALDO_AUX-@QTD_ATEND  
			  SET @TESTE='2'
			  END
		--IF PARA INSERIR APENAS RETORNO COM SALDO>=0 E QTD_ATEND>0  
        IF @SALDO_AUX>=0 AND @QTD_ATEND>0
	      BEGIN
				SELECT @COD_MAT_NECES COD_MAT_NECES,@QTD_LOTE QTD_LOTE,@LOTE LOTE,
				       @QTD_NECES_CONS QTD_NECES_CONS,@SALDO SALDO,
					   @SALDO_AUX SALDO_AUX,@QTD_ATEND BAIXA,@TESTE TESTE
		--EXCUTANDO PROCEDURE DE MOV ESTOQUE DENTRO DO IF, RECEBENDO VARIAVEIS
		 --INSERT NA TABELA CONSUMO PARA RASTREABILIDADE
		  INSERT INTO CONSUMO VALUES (@COD_EMPRESA,@ID_APON,@COD_MAT_NECES,@QTD_ATEND,@LOTE)
		
		--EXECUTA PROC GERA ESTOQUE COM MOV SAIDA
		EXEC PROC_GERA_ESTOQUE @COD_EMPRESA,'S',@COD_MAT_NECES,@LOTE,@QTD_ATEND,@DATA_MOVTO
		--ATRIBUINDO VALOR VARIAVEL 
		SET @COD_MAT_AUX=@COD_MAT_NECES;
	    END
    --TESTE
		
		FETCH NEXT FROM ESTOQUE_CONSUMO
		INTO @COD_MAT_NECES,@QTD_LOTE,@LOTE,@QTD_NECES_CONS
	END
	CLOSE ESTOQUE_CONSUMO
	DEALLOCATE ESTOQUE_CONSUMO

	    FETCH NEXT FROM NECESSIDADES
		INTO @ID_ORDEM,@SITUACAO,@COD_MAT_PROD,
			 @QTD_PLAN,@COD_MAT_NECES,@QTD_NECES,
			 @QTD_APON,@QTD_NECES_CONS

	END 
	CLOSE NECESSIDADES
	DEALLOCATE NECESSIDADES

	END TRY --END TRY
    BEGIN CATCH
        SET @ERRO_INTERNO =5;
        print ''
        print 'Erro ocorreu!'
        print 'Mensagem: ' + ERROR_MESSAGE()
        print 'Procedure: ' + ERROR_PROCEDURE()

		IF (SELECT CURSOR_STATUS('global', 'APONT')) = 1 
		BEGIN
			CLOSE APONT	
			DEALLOCATE APONT	
		END
		IF (SELECT CURSOR_STATUS('global', 'ESTOQUE_CONSUMO')) = 1 
		BEGIN
			CLOSE ESTOQUE_CONSUMO	
			DEALLOCATE ESTOQUE_CONSUMO	
		END
		IF (SELECT CURSOR_STATUS('global', 'NECESSIDADES')) = 1 
		BEGIN
			CLOSE NECESSIDADES	
			DEALLOCATE NECESSIDADES	
		END	
		
		SET XACT_ABORT ON;
		IF @@TRANCOUNT > 0  
        ROLLBACK TRANSACTION; 

END CATCH
END --FIM DO PRIMEIRO IF
--CONSIDERACOES FINAIS
IF (SELECT A.QTD_PLAN-A.QTD_PROD SALDO FROM ORDEM_PROD A 
    WHERE  COD_EMPRESA=@COD_EMPRESA AND A.ID_ORDEM=@ID_ORDEM AND A.SITUACAO='P')=0
	BEGIN
		UPDATE ORDEM_PROD SET SITUACAO='F' 
		WHERE COD_EMPRESA=@COD_EMPRESA 
		AND ID_ORDEM=@ID_ORDEM
		AND SITUACAO='P'
		SELECT 'ORDEM FINALIZADA' 
	END


--ULTIMAS TESTES
     IF @@ERROR <> 0 
		BEGIN
		  ROLLBACK
		  PRINT @@error
		  PRINT 'OPERACAO CANCELADA' 
		END
	 ELSE IF @ERRO_INTERNO=1
	 BEGIN
		PRINT 'ORDEM NAO EXISTE OU SEM SALDO/PARAMETROS INCORRETOS'
		ROLLBACK
	 END
	 ELSE IF @ERRO_INTERNO=2
	 BEGIN
		PRINT 'SALDO INSUFICIENTE DA ORDEM'
		ROLLBACK
	 END
	 ELSE IF @ERRO_INTERNO=3
	 BEGIN
		PRINT 'MATERIAIS NECESSARIOS INSUFICENTE'
		ROLLBACK
	 END
	  ELSE IF @ERRO_INTERNO=5
	 BEGIN
		PRINT 'ERRO PROCEDURE DE ESTOQUE'
		ROLLBACK
	 END

	 ELSE
		BEGIN
			COMMIT
		    PRINT 'APONTAMENTO CONCLUIDA'
		END 

END --FIM PROCEDURE

--TESTANDO A PROCEDURE
--PARAMETROS @COD_EMPRESA @ID_ORDEM,@COD_MAT_PROD,@QTD_APON,@LOTE_PROD

EXEC PROC_APONTAMENTO 2,1,1,10,'TESTE1'
EXEC PROC_APONTAMENTO 1,1,2,10,'TESTE1'

EXEC PROC_APONTAMENTO 1,1,1,40,'TESTE1'

EXEC PROC_APONTAMENTO 1,1,1,10,'TESTE1'
EXEC PROC_APONTAMENTO 1,1,1,25,'TESTE2'


SELECT *  from ORDEM_PROD
select * from ESTOQUE
select * from ESTOQUE_LOTE
SELECT * FROM ESTOQUE_MOV
SELECT * FROM APONTAMENTOS
SELECT * FROM CONSUMO