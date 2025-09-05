--!strict

local GuiService = game:GetService("GuiService")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

export type CameraState = "Menu" | "Board"

local CAMERA_PAN_FACTOR = 16

local CameraController = {
	camPos = Vector3.new(),
	camFocus = Vector3.new(),
} :: {
	[string]: (...any) -> ...any,
	camPos: Vector3,
	camFocus: Vector3,
}

local Camera = workspace.CurrentCamera
local cameraState: CameraState = "Menu"

function CameraController.fitPartToFrame(Part: BasePart, Frame: Frame): CFrame
	local topBarOffset = GuiService.TopbarInset.Height
	local framePosX = Frame.AbsolutePosition.X + Frame.AbsoluteSize.X / 2
	local framePosY = (Frame.AbsolutePosition.Y + topBarOffset) + Frame.AbsoluteSize.Y / 2

	local zBaseOffset = Part.Size.X
		/ (
			2
			* math.tan(math.rad(Camera.FieldOfView) / 2)
			* (Frame.AbsoluteSize.Y / Camera.ViewportSize.Y)
		)
	local unitRay = Camera:ViewportPointToRay(framePosX, framePosY, zBaseOffset)

	unitRay = Camera:ViewportPointToRay(
		framePosX,
		framePosY,
		zBaseOffset / math.cos(unitRay.Direction:Angle(Camera.CFrame.LookVector))
	)

	-- Apply and fix CFrame towards camera
	local baseCF = CFrame.new(unitRay.Origin)
	local x, y, z = Camera.CFrame:ToEulerAnglesXYZ()
	baseCF *= CFrame.Angles(x, y, z)
	baseCF *= CFrame.Angles(0, math.pi, 0) -- Flip part around so front faces camera

	return baseCF
end

function CameraController.changeState(newState: CameraState) cameraState = newState end

function CameraController.init() end

function CameraController.start()
	Camera.FieldOfView = 15 --TODO: make this variable
	Camera.CameraType = Enum.CameraType.Scriptable

	-- Camera loop
	RunService.Heartbeat:Connect(function(dt: number)
		Camera.CameraType = Enum.CameraType.Scriptable
		local screenSize = Camera.ViewportSize
		local screenCenter = screenSize / 2
		local camFocusDist = (CameraController.camPos - CameraController.camFocus).Magnitude
		local mouseDriftMag = camFocusDist * 0.0075
		local mousePos = UserInputService:GetMouseLocation() - screenCenter
		local mouseOffsetCF = CFrame.new(
			mousePos.X / screenSize.X * mouseDriftMag,
			-mousePos.Y / screenSize.Y * mouseDriftMag,
			0
		)
		local targCamCF = CFrame.lookAt(CameraController.camPos, CameraController.camFocus)
			* mouseOffsetCF
		Camera.CFrame = Camera.CFrame:Lerp(targCamCF, 1 - math.exp(-CAMERA_PAN_FACTOR * dt))
	end)
end

return CameraController
